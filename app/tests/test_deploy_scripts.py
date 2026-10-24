"""Tests for the deploy safety checks: scripts/check_deploy_plan.py and scripts/verify_deploy.py."""

import copy
import importlib.util
import json
import sys
import threading
from collections.abc import Iterator
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

REPO = Path(__file__).resolve().parents[2]


def load(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, REPO / "scripts" / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


check_plan = load("check_deploy_plan")
verify = load("verify_deploy")

OLD = "sha256:" + "a" * 64
NEW = "sha256:" + "b" * 64
REGISTRY = "123456789012.dkr.ecr.us-east-1.amazonaws.com/portfolio-api"


def function_update(**after_overrides: Any) -> dict[str, Any]:
    before = {
        "function_name": "portfolio-api",
        "image_uri": f"{REGISTRY}@{OLD}",
        "memory_size": 512,
        "timeout": 10,
        "architectures": ["x86_64"],
        "reserved_concurrent_executions": 2,
        "code_sha256": OLD.removeprefix("sha256:"),
        "version": "$LATEST",
    }
    after = {**before, "image_uri": f"{REGISTRY}@{NEW}", "code_sha256": None, "version": None}
    after.update(after_overrides)
    return {
        "address": "aws_lambda_function.api[0]",
        "change": {
            "actions": ["update"],
            "before": before,
            "after": after,
            # Computed after the apply, so they are not inputs.
            "after_unknown": {"code_sha256": True, "version": True, "last_modified": True},
        },
    }


def untouched(address: str) -> dict[str, Any]:
    return {"address": address, "change": {"actions": ["no-op"], "before": {}, "after": {}}}


def plan_with(*changes: dict[str, Any]) -> dict[str, Any]:
    return {"resource_changes": [untouched("aws_ecr_repository.api"), *changes]}


def test_an_image_only_update_passes() -> None:
    found, changes = check_plan.problems(plan_with(function_update()), NEW)
    assert found == [] and changes is True


def test_a_plan_with_no_changes_passes_and_says_so() -> None:
    found, changes = check_plan.problems(plan_with(untouched("aws_lambda_function.api[0]")), NEW)
    assert found == [] and changes is False


@pytest.mark.parametrize(
    ("actions", "why"),
    [
        (["delete"], "delete"),
        (["create"], "create"),
        (["delete", "create"], "create, delete"),
    ],
)
def test_anything_but_an_in_place_update_of_the_function_fails(
    actions: list[str], why: str
) -> None:
    resource = function_update()
    resource["change"]["actions"] = actions
    found, _ = check_plan.problems(plan_with(resource), NEW)
    assert len(found) == 1 and why in found[0]


def test_a_change_to_any_other_resource_fails() -> None:
    other = {
        "address": "aws_ecr_repository.api",
        "change": {
            "actions": ["update"],
            "before": {"force_delete": False},
            "after": {"force_delete": True},
        },
    }
    found, _ = check_plan.problems(plan_with(function_update(), other), NEW)
    assert len(found) == 1 and "aws_ecr_repository.api" in found[0]


def test_only_the_function_may_change_even_if_the_change_looks_like_an_image_swap() -> None:
    """The address guard must hold on its own, not only because of the attribute check."""
    lookalike = function_update()
    lookalike["address"] = "aws_lambda_function.other[0]"
    found, _ = check_plan.problems(plan_with(lookalike), NEW)
    assert len(found) == 1 and "only aws_lambda_function.api[0] may" in found[0]


@pytest.mark.parametrize(
    "override",
    [{"memory_size": 1024}, {"timeout": 30}, {"reserved_concurrent_executions": None}],
)
def test_changing_anything_besides_the_image_fails(override: dict[str, Any]) -> None:
    found, _ = check_plan.problems(plan_with(function_update(**override)), NEW)
    assert len(found) == 1 and "only image_uri may" in found[0]


def test_an_image_that_is_not_the_approved_digest_fails() -> None:
    found, _ = check_plan.problems(plan_with(function_update()), "sha256:" + "c" * 64)
    assert len(found) == 1 and "not the approved digest" in found[0]


@pytest.mark.parametrize("digest", ["latest", "sha256:abc", "", NEW.upper()])
def test_a_malformed_digest_is_rejected(digest: str) -> None:
    found, changes = check_plan.problems(plan_with(function_update()), digest)
    assert len(found) == 1 and changes is False


def test_main_writes_the_result_for_the_workflow(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(json.dumps(plan_with(function_update())), encoding="utf-8")
    output = tmp_path / "output"
    monkeypatch.setenv("GITHUB_OUTPUT", str(output))
    assert check_plan.main([str(plan_file), NEW]) == 0
    assert output.read_text(encoding="utf-8") == "changes=true\n"


def test_main_fails_on_an_unsafe_or_unreadable_plan(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("GITHUB_OUTPUT", str(tmp_path / "output"))
    unsafe = plan_with(function_update(memory_size=1024))
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(json.dumps(unsafe), encoding="utf-8")
    assert check_plan.main([str(plan_file), NEW]) == 1
    assert not (tmp_path / "output").exists()  # no "changes=" line for an unsafe plan

    plan_file.write_text("not json", encoding="utf-8")
    assert check_plan.main([str(plan_file), NEW]) == 1
    assert check_plan.main([str(tmp_path / "missing.json"), NEW]) == 1
    assert check_plan.main([]) == 2


def test_the_checker_does_not_modify_the_plan() -> None:
    plan = plan_with(function_update())
    snapshot = copy.deepcopy(plan)
    check_plan.problems(plan, NEW)
    assert plan == snapshot


# ------------------------------------------------------------------ verify_deploy.py

COMMIT = "0123456789abcdef0123456789abcdef01234567"
OTHER_COMMIT = "f" * 40


@contextmanager
def api(responses: list[tuple[int, dict[str, Any]]]) -> Iterator[str]:
    """A local server that answers /health with the given responses, in order (the last repeats)."""
    calls = {"count": 0}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - the name is fixed by BaseHTTPRequestHandler
            status, body = responses[min(calls["count"], len(responses) - 1)]
            calls["count"] += 1
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


HEALTHY = (200, {"status": "ok", "version": "0.0.0-dev", "git_sha": COMMIT})


def test_a_healthy_api_on_the_expected_commit_verifies() -> None:
    with api([HEALTHY]) as url:
        assert verify.main([url, COMMIT, "1", "0"]) == 0


def test_the_wrong_commit_does_not_verify() -> None:
    with api([(200, {"status": "ok", "git_sha": OTHER_COMMIT})]) as url:
        assert verify.main([url, COMMIT, "2", "0"]) == 1


@pytest.mark.parametrize(
    "response",
    [
        (500, {"detail": "boom"}),
        (200, {"status": "degraded", "git_sha": COMMIT}),
        (200, {"git_sha": COMMIT}),
    ],
)
def test_an_unhealthy_api_does_not_verify(response: tuple[int, dict[str, Any]]) -> None:
    with api([response]) as url:
        assert verify.main([url, COMMIT, "2", "0"]) == 1


def test_it_waits_for_a_cold_or_still_updating_function() -> None:
    old = (200, {"status": "ok", "git_sha": OTHER_COMMIT})
    with api([(500, {}), old, HEALTHY]) as url:
        assert verify.main([url, COMMIT, "5", "0"]) == 0


def test_an_unreachable_api_does_not_verify() -> None:
    assert verify.main(["http://127.0.0.1:1", COMMIT, "1", "0"]) == 1


@pytest.mark.parametrize(
    "argv",
    [
        [],
        ["http://example.com", COMMIT],  # plain http to a remote host
        ["https://example.com", "main"],  # not a full commit hash
        ["https://example.com", COMMIT[:7]],
    ],
)
def test_bad_arguments_are_rejected_before_any_request(argv: list[str]) -> None:
    assert verify.main(argv) == 2

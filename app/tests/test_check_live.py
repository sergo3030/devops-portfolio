"""Tests for the standing check of the deployed site and API: scripts/check_live.py."""

import importlib.util
import json
import sys
import threading
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import pytest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_live", REPO / "scripts" / "check_live.py")
assert spec is not None and spec.loader is not None
live = importlib.util.module_from_spec(spec)
sys.modules["check_live"] = live
spec.loader.exec_module(live)

COMMIT = "0123456789abcdef0123456789abcdef01234567"
CONTENT = {
    "version": 1,
    "profile": {"name": "Test Person"},
    "links": [],
    "skills": [{"name": "Python"}],
    "experience": [],
    "case_studies": [],
    "languages": [],
}
SECURITY = {
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
    "Strict-Transport-Security": "max-age=31536000",
}


@dataclass
class Fake:
    """What the fake API does. A test changes one thing and the check must notice."""

    site_origin: str = ""
    health_status: int = 200
    health: dict[str, Any] = field(
        default_factory=lambda: {"status": "ok", "version": "0.1.1", "git_sha": COMMIT}
    )
    content: dict[str, Any] = field(default_factory=lambda: dict(CONTENT))
    content_cache: str = "public, max-age=300"
    health_cache: str = "no-store"
    cors: str = "site"  # "site", "wildcard", "everyone", "credentials" or "none"
    drop: set[str] = field(default_factory=set)
    server_banner: str | None = None
    post_status: int = 405
    post_allow: str | None = "GET, OPTIONS"
    failures_first: int = 0  # answer /health with a 500 this many times before behaving
    health_calls: int = 0


@contextmanager
def world(fake: Fake, policy: str | None = "{api}") -> Iterator[str]:
    """A fake API and a fake site whose page points at it. Yields the site URL.

    `policy` is the connect-src value; "{api}" is replaced with the API's origin, and None leaves
    the Content-Security-Policy out of the page altogether.
    """

    class Api(BaseHTTPRequestHandler):
        def send(self, status: int, body: Any, cache: str | None, extra: dict[str, str]) -> None:
            data = json.dumps(body).encode()
            headers = {"Content-Type": "application/json", **SECURITY, **extra}
            if cache:
                headers["Cache-Control"] = cache
            if fake.server_banner:
                headers["Server"] = fake.server_banner
            for name in fake.drop:
                headers.pop(name, None)
            self.send_response(status)
            for name, value in headers.items():
                self.send_header(name, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def cors_headers(self) -> dict[str, str]:
            origin = self.headers.get("Origin", "")
            if fake.cors == "none" or not origin:
                return {}
            if fake.cors == "wildcard":
                return {"Access-Control-Allow-Origin": "*"}
            if fake.cors == "everyone" or origin == fake.site_origin:
                result = {"Access-Control-Allow-Origin": origin}
                if fake.cors == "credentials":
                    result["Access-Control-Allow-Credentials"] = "true"
                return result
            return {}

        def do_GET(self) -> None:  # noqa: N802 - the name is fixed by BaseHTTPRequestHandler
            if self.path == "/health":
                fake.health_calls += 1
                if fake.health_calls <= fake.failures_first:
                    self.send(500, {"detail": "boom"}, "no-store", {})
                    return
                self.send(fake.health_status, fake.health, fake.health_cache, self.cors_headers())
            elif self.path == "/content":
                self.send(200, fake.content, fake.content_cache, self.cors_headers())
            else:
                self.send(404, {"detail": "Not Found"}, "no-store", {})

        def do_POST(self) -> None:  # noqa: N802
            extra = {"Allow": fake.post_allow} if fake.post_allow else {}
            self.send(fake.post_status, {"detail": "Method Not Allowed"}, "no-store", extra)

        def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
            return

    api_server = ThreadingHTTPServer(("127.0.0.1", 0), Api)
    api_origin = f"http://127.0.0.1:{api_server.server_port}"

    class Site(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            if policy is None:
                page = "<html><head></head><body>no policy</body></html>"
            else:
                connect = policy.replace("{api}", api_origin)
                csp = f"default-src 'self'; connect-src 'self' {connect}".strip()
                page = (
                    '<html><head><meta http-equiv="Content-Security-Policy" '
                    f'content="{csp}" /></head><body>site</body></html>'
                )
            data = page.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
            return

    site_server = ThreadingHTTPServer(("127.0.0.1", 0), Site)
    fake.site_origin = f"http://127.0.0.1:{site_server.server_port}"
    servers = [api_server, site_server]
    threads = [
        threading.Thread(target=s.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        for s in servers
    ]
    for thread in threads:
        thread.start()
    try:
        yield fake.site_origin + "/devops-portfolio/"
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join(timeout=5)


def problems_of(fake: Fake, policy: str | None = "{api}") -> list[str]:
    with world(fake, policy) as site_url:
        return live.check_once(site_url).problems


def test_a_healthy_site_and_api_pass() -> None:
    fake = Fake()
    with world(fake) as site_url:
        report = live.check_once(site_url)
        assert report.problems == []
        assert any("version 0.1.1" in fact for fact in report.facts)
        assert live.main([site_url, "1", "0"]) == 0


# ------------------------------------------------------------------ the site


def test_a_page_without_a_policy_fails() -> None:
    assert any("no Content-Security-Policy" in p for p in problems_of(Fake(), policy=None))


@pytest.mark.parametrize("policy", ["", "https://one.example https://two.example", "{api} {api}x"])
def test_a_page_that_does_not_name_exactly_one_api_origin_fails(policy: str) -> None:
    assert any("exactly one API origin" in p for p in problems_of(Fake(), policy=policy))


def test_a_page_pointing_at_an_address_without_a_scheme_or_with_a_path_fails() -> None:
    assert any("not a plain https origin" in p for p in problems_of(Fake(), policy="{api}/path"))
    assert any(
        "not a plain https origin" in p for p in problems_of(Fake(), policy="http://example.com")
    )


def test_a_site_pointing_at_an_api_that_is_gone_fails() -> None:
    problems = problems_of(Fake(), policy="http://127.0.0.1:1")
    assert any(p.startswith("/health: no answer") for p in problems)
    assert any(p.startswith("/content: no answer") for p in problems)


def test_a_site_that_does_not_answer_fails() -> None:
    assert live.check_once("http://127.0.0.1:1/").problems[0].startswith("site: no answer")


# ------------------------------------------------------------------ the API


@pytest.mark.parametrize(
    ("fake", "expected"),
    [
        (Fake(health_status=500), "/health"),
        (Fake(health={"status": "degraded", "version": "0.1.1", "git_sha": COMMIT}), "/health"),
        (Fake(health={"status": "ok", "git_sha": COMMIT}), "/health"),  # no version
        (Fake(health={"status": "ok", "version": "<script>", "git_sha": COMMIT}), "/health"),
        (Fake(health={"status": "ok", "version": "0.1.1", "git_sha": "abc"}), "/health"),
        (Fake(health_cache="public, max-age=300"), "/health cache"),
        (Fake(content={k: v for k, v in CONTENT.items() if k != "skills"}), "/content"),
        (
            Fake(content={**CONTENT, "profile": {"name": "x", "approved": True}}),
            "/content approval state",
        ),
        (
            Fake(content={**CONTENT, "case_studies": [{"employer_approval": "yes"}]}),
            "/content approval state",
        ),
        (Fake(content_cache="no-store"), "/content cache"),
        (Fake(cors="none"), "/health CORS"),
        (Fake(cors="wildcard"), "/health CORS"),
        (Fake(cors="credentials"), "/health CORS"),
        (Fake(cors="everyone"), "CORS for another website"),
        (Fake(cors="wildcard"), "CORS for another website"),
        (Fake(drop={"X-Content-Type-Options"}), "/health headers"),
        (Fake(drop={"Content-Security-Policy"}), "/health headers"),
        (Fake(drop={"Strict-Transport-Security"}), "/health headers"),
        (Fake(server_banner="uvicorn"), "/health headers"),
        (Fake(post_status=200), "write refused"),
        (Fake(post_allow=None), "write refused"),
    ],
)
def test_each_way_the_api_can_be_wrong_is_noticed(fake: Fake, expected: str) -> None:
    problems = problems_of(fake)
    assert any(p.startswith(expected) for p in problems), problems


def test_a_server_banner_that_is_not_ours_is_fine() -> None:
    """The platform in front of the function may add its own banner. Only our own is a leak."""
    assert problems_of(Fake(server_banner="AmazonS3")) == []


# ------------------------------------------------------------------ the run


def test_a_cold_start_is_waited_out() -> None:
    fake = Fake(failures_first=1)
    with world(fake) as site_url:
        assert live.main([site_url, "3", "0"]) == 0
        assert fake.health_calls >= 2


def test_it_gives_up_after_the_last_attempt(capsys: pytest.CaptureFixture[str]) -> None:
    fake = Fake(health_status=500)
    with world(fake) as site_url:
        assert live.main([site_url, "2", "0"]) == 1
    error = capsys.readouterr().err
    assert "FAIL /health" in error
    assert "attempt 2/2" in error
    assert "live check FAILED" in error


def test_the_result_goes_to_the_job_summary(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    summary = tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    with world(Fake()) as site_url:
        assert live.main([site_url, "1", "0"]) == 0
    text = summary.read_text(encoding="utf-8")
    assert "result: passed" in text
    assert "version 0.1.1" in text

    summary.unlink()
    with world(Fake(health_status=500)) as site_url:
        assert live.main([site_url, "1", "0"]) == 1
    assert "FAIL: /health" in summary.read_text(encoding="utf-8")


@pytest.mark.parametrize(
    "argv", [[], ["http://example.com"], ["https://a.example", "1", "0", "extra"]]
)
def test_bad_arguments_are_rejected_before_any_request(argv: list[str]) -> None:
    assert live.main(argv) == 2

"""Tests for the API: behaviour, start-up, the contract with the content build, the leak guard."""

import importlib
import importlib.util
import json
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest
import yaml
from fastapi.testclient import TestClient
from pydantic import ValidationError

import portfolio_api.main as main_module
from portfolio_api.content import ContentError, content_store, get_content, load_content
from portfolio_api.main import app
from portfolio_api.models import Content

REPO = Path(__file__).resolve().parents[2]
CONTENT_YAML = REPO / "content" / "content.yaml"


def _load_checker() -> Any:
    spec = importlib.util.spec_from_file_location(
        "check_content_for_api", REPO / "scripts" / "check_content.py"
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["check_content_for_api"] = module
    spec.loader.exec_module(module)
    return module


def published_content() -> dict[str, Any]:
    """The real content, built exactly as the CI and the image build do it."""
    source = yaml.safe_load(CONTENT_YAML.read_text(encoding="utf-8"))
    built: dict[str, Any] = _load_checker().build_public(source)
    return built


def sample_content() -> dict[str, Any]:
    return {
        "version": 1,
        "profile": {"name": "Test Person", "title": "DevOps Engineer"},
        "links": [{"label": "GitHub", "url": "https://github.com/example"}],
        "skills": [{"category": "Containers", "items": ["Kubernetes", "Helm"]}],
        "experience": [
            {
                "employer": "Example Corp",
                "role": "DevOps Engineer",
                "start": "2024-03",
                "end": "present",
                "bullets": ["Did a thing."],
            }
        ],
        "case_studies": [
            {
                "id": "study",
                "title": "A study",
                "summary": "Short.",
                "sections": [{"heading": "Context", "paragraphs": ["Text."]}],
            }
        ],
        "languages": ["English"],
    }


def write(tmp_path: Path, data: dict[str, Any]) -> Path:
    path = tmp_path / "content.public.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    # The content is loaded in the lifespan, which TestClient only runs inside `with`.
    monkeypatch.setenv("CONTENT_FILE", str(write(tmp_path, sample_content())))
    with TestClient(app) as test_client:
        yield test_client


def test_health(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_content_is_served_with_a_cache_header(client: TestClient) -> None:
    response = client.get("/content")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=300"
    body = response.json()
    assert body["profile"] == {
        "name": "Test Person",
        "title": "DevOps Engineer",
        "summary": None,
        "country": None,
    }
    assert body["skills"][0]["items"] == ["Kubernetes", "Helm"]


def test_wrong_method_and_unknown_path(client: TestClient) -> None:
    assert client.post("/content").status_code == 405
    assert client.get("/nope").status_code == 404


def test_the_content_dependency_can_be_overridden(client: TestClient) -> None:
    replacement = Content.model_validate({**sample_content(), "languages": ["Hebrew"]})
    app.dependency_overrides[get_content] = lambda: replacement
    try:
        assert client.get("/content").json()["languages"] == ["Hebrew"]
    finally:
        app.dependency_overrides.clear()


def test_docs_are_off_by_default(client: TestClient) -> None:
    assert client.get("/docs").status_code == 404
    assert client.get("/redoc").status_code == 404
    assert client.get("/openapi.json").status_code == 404


def test_docs_are_on_when_enabled_by_the_environment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("CONTENT_FILE", str(write(tmp_path, sample_content())))
    monkeypatch.setenv("ENABLE_DOCS", "1")
    reloaded = importlib.reload(main_module)  # the docs flag is read when the module is imported
    try:
        with TestClient(reloaded.app) as enabled:
            assert enabled.get("/openapi.json").status_code == 200
    finally:
        monkeypatch.delenv("ENABLE_DOCS")
        importlib.reload(main_module)


def test_importing_the_module_does_no_file_io(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The content is read in the lifespan, so importing never needs the file."""
    monkeypatch.setenv("CONTENT_FILE", str(tmp_path / "absent.json"))
    importlib.reload(main_module)  # must not raise


def test_missing_content_aborts_the_start_up_with_a_helpful_message(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("CONTENT_FILE", str(tmp_path / "absent.json"))
    with pytest.raises(ContentError, match="just content-build"), TestClient(app):
        pass  # entering the client runs the lifespan start-up


def test_invalid_content_aborts_the_start_up(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    broken = sample_content()
    del broken["profile"]
    monkeypatch.setenv("CONTENT_FILE", str(write(tmp_path, broken)))
    with pytest.raises(ContentError, match="invalid"), TestClient(app):
        pass


def test_content_is_cleared_on_shutdown(client: TestClient) -> None:
    assert content_store.get().version == 1
    client.__exit__(None, None, None)
    with pytest.raises(ContentError, match="not loaded"):
        content_store.get()


def test_load_content_rejects_broken_files(tmp_path: Path) -> None:
    not_json = tmp_path / "bad.json"
    not_json.write_text("{ not json", encoding="utf-8")
    with pytest.raises(ContentError, match="invalid"):
        load_content(not_json)
    broken = sample_content()
    del broken["skills"]
    with pytest.raises(ContentError, match="invalid"):
        load_content(write(tmp_path, broken))


def test_models_reject_unknown_fields() -> None:
    extra = sample_content()
    extra["approved"] = True
    with pytest.raises(ValidationError):
        Content.model_validate(extra)
    leaky = sample_content()
    leaky["case_studies"][0]["employer_approval"] = "granted"
    with pytest.raises(ValidationError):
        Content.model_validate(leaky)


def test_the_real_content_build_matches_the_models() -> None:
    """Contract: what the build publishes is exactly what the API can serve."""
    Content.model_validate(published_content())


def test_the_api_never_serves_approval_state_or_unapproved_case_studies(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = yaml.safe_load(CONTENT_YAML.read_text(encoding="utf-8"))
    monkeypatch.setenv("CONTENT_FILE", str(write(tmp_path, published_content())))
    with TestClient(app) as live:
        served = live.get("/content")
    body = served.json()
    assert "approved" not in served.text
    assert "employer_approval" not in served.text
    allowed_ids = {
        study["id"]
        for study in source["case_studies"]
        if study["approved"] is True and study["employer_approval"] == "granted"
    }
    assert {study["id"] for study in body["case_studies"]} <= allowed_ids

"""Tests for the hardening of the API: CORS, security headers, the read-only rule, the settings."""

import importlib
import json
import re
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import portfolio_api.main as main_module
from portfolio_api.config import SettingsError, get_settings

REPO = Path(__file__).resolve().parents[2]
SITE = "https://sergo3030.github.io"
OTHER = "https://evil.example"

CONTENT = {
    "version": 1,
    "profile": {"name": "Test Person"},
    "links": [],
    "skills": [],
    "experience": [],
    "case_studies": [],
    "languages": [],
}

SECURITY_HEADERS = {
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
    "referrer-policy": "no-referrer",
    "x-frame-options": "DENY",
    "strict-transport-security": "max-age=31536000",
}


@contextmanager
def served(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, origins: str | None = SITE
) -> Iterator[TestClient]:
    """The API as it would run with CORS_ALLOW_ORIGINS set (the module reads it when imported)."""
    content = tmp_path / "content.public.json"
    content.write_text(json.dumps(CONTENT), encoding="utf-8")
    monkeypatch.setenv("CONTENT_FILE", str(content))
    if origins is None:
        monkeypatch.delenv("CORS_ALLOW_ORIGINS", raising=False)
    else:
        monkeypatch.setenv("CORS_ALLOW_ORIGINS", origins)
    reloaded = importlib.reload(main_module)
    try:
        with TestClient(reloaded.app) as client:
            yield client
    finally:
        monkeypatch.delenv("CORS_ALLOW_ORIGINS", raising=False)
        importlib.reload(main_module)


@pytest.fixture
def api(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    with served(tmp_path, monkeypatch) as client:
        yield client


# ------------------------------------------------------------------ CORS


def test_the_site_may_read_the_api_from_a_browser(api: TestClient) -> None:
    response = api.get("/content", headers={"Origin": SITE})
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == SITE
    assert "origin" in response.headers["vary"].lower()
    assert "access-control-allow-credentials" not in response.headers


@pytest.mark.parametrize(
    "origin",
    [OTHER, "null", "https://sergo3030.github.io.evil.example", "http://sergo3030.github.io"],
)
def test_other_websites_get_no_cors_headers(api: TestClient, origin: str) -> None:
    response = api.get("/content", headers={"Origin": origin})
    assert (
        response.status_code == 200
    )  # the API still answers (curl does), a browser just may not read it
    assert not any(name.startswith("access-control-") for name in response.headers)


def test_the_api_never_answers_with_a_wildcard_origin(api: TestClient) -> None:
    assert (
        api.get("/health", headers={"Origin": SITE}).headers["access-control-allow-origin"] != "*"
    )


def test_a_preflight_from_the_site_for_get_is_answered(api: TestClient) -> None:
    response = api.options(
        "/content",
        headers={
            "Origin": SITE,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "accept, cache-control",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == SITE
    assert set(response.headers["access-control-allow-methods"].split(", ")) == {"GET", "OPTIONS"}
    assert response.headers["access-control-max-age"] == "600"


@pytest.mark.parametrize(
    ("origin", "method", "requested_headers"),
    [
        (SITE, "POST", "accept"),
        (SITE, "DELETE", "accept"),
        (SITE, "GET", "authorization"),
        (SITE, "GET", "x-api-key"),
        (OTHER, "GET", "accept"),
    ],
)
def test_other_preflights_are_refused(
    api: TestClient, origin: str, method: str, requested_headers: str
) -> None:
    response = api.options(
        "/content",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": method,
            "Access-Control-Request-Headers": requested_headers,
        },
    )
    assert response.status_code == 400
    # For the site's own origin the framework still names the origin in the refusal, but what the
    # browser may do is only ever what the allow lists say, and these requests are not in them.
    allowed_methods = response.headers.get("access-control-allow-methods", "")
    allowed_headers = response.headers.get("access-control-allow-headers", "").lower()
    if origin == OTHER:
        assert "access-control-allow-origin" not in response.headers
    assert method not in allowed_methods.split(", ") or method == "GET"
    assert requested_headers not in allowed_headers.split(", ") or requested_headers == "accept"
    if method != "GET":
        assert "Disallowed CORS method" in response.text
    if requested_headers not in ("accept", "cache-control"):
        assert "Disallowed CORS headers" in response.text


def test_without_configuration_there_are_no_cors_headers_at_all(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    with served(tmp_path, monkeypatch, origins=None) as client:
        response = client.get("/content", headers={"Origin": SITE})
        assert not any(name.startswith("access-control-") for name in response.headers)
        preflight = client.options(
            "/content", headers={"Origin": SITE, "Access-Control-Request-Method": "GET"}
        )
        assert "access-control-allow-origin" not in preflight.headers


def test_several_origins_can_be_configured(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    with served(tmp_path, monkeypatch, origins=f"{SITE}, http://localhost:5173") as client:
        for origin in (SITE, "http://localhost:5173"):
            assert (
                client.get("/health", headers={"Origin": origin}).headers[
                    "access-control-allow-origin"
                ]
                == origin
            )
        assert (
            "access-control-allow-origin"
            not in client.get("/health", headers={"Origin": OTHER}).headers
        )


# ------------------------------------------------------------------ security headers


def assert_hardened(response: object) -> None:
    headers = {name.lower(): value for name, value in response.headers.items()}  # type: ignore[attr-defined]
    for name, value in SECURITY_HEADERS.items():
        assert headers.get(name) == value, name
    assert "server" not in headers or "uvicorn" not in headers["server"].lower()


def test_every_kind_of_response_carries_the_security_headers(api: TestClient) -> None:
    responses = [
        api.get("/health"),
        api.get("/content"),
        api.get("/nope"),  # 404 from the framework
        api.post("/content"),  # 405 from the read-only rule
        api.request("GET", "/health", content=b"x"),  # 413
        api.get("/content", headers={"Origin": SITE}),  # a CORS answer
        api.options("/content", headers={"Origin": OTHER, "Access-Control-Request-Method": "GET"}),
        api.get("/docs"),  # off by default
    ]
    assert [r.status_code for r in responses] == [200, 200, 404, 405, 413, 200, 400, 404]
    for response in responses:
        assert_hardened(response)


def test_only_the_content_may_be_cached(api: TestClient) -> None:
    assert api.get("/content").headers["cache-control"] == "public, max-age=300"
    for response in (api.get("/health"), api.get("/nope"), api.post("/content")):
        assert response.headers["cache-control"] == "no-store"


# ------------------------------------------------------------------ read-only


@pytest.mark.parametrize("method", ["POST", "PUT", "PATCH", "DELETE", "HEAD", "TRACE"])
def test_only_get_and_options_are_allowed(api: TestClient, method: str) -> None:
    response = api.request(method, "/content")
    assert response.status_code == 405
    assert response.headers["allow"] == "GET, OPTIONS"


def test_a_request_with_a_body_is_refused_before_anything_reads_it(api: TestClient) -> None:
    assert api.request("GET", "/health", content=b"x" * 5000).status_code == 413
    assert api.request("GET", "/health", content=b"{}").status_code == 413


def test_a_chunked_body_is_refused(api: TestClient) -> None:
    def chunks() -> Iterator[bytes]:
        yield b"abc"

    assert api.request("GET", "/health", content=chunks()).status_code == 413


def test_oversized_headers_and_urls_are_refused(api: TestClient) -> None:
    big = api.get("/health", headers={"X-Big": "a" * 20_000})
    assert big.status_code == 431
    assert api.get("/health", headers={"X-Medium": "a" * 4_000}).status_code == 200
    assert api.get("/health?" + "q=a&" * 700).status_code == 414  # 2.8 KB of query
    assert api.get("/health?x=" + "a" * 1_000).status_code == 200


def test_an_empty_body_is_fine(api: TestClient) -> None:
    assert api.get("/health", headers={"Content-Length": "0"}).status_code == 200


# ------------------------------------------------------------------ settings


@pytest.mark.parametrize(
    "value",
    [
        "*",
        "https://*.example.com",
        "https://sergo3030.github.io/",
        "https://sergo3030.github.io/devops-portfolio",
        "http://example.com",
        "ftp://example.com",
        "sergo3030.github.io",
        "https://Sergo3030.github.io",
        f"{SITE},*",
        "https://exa mple.com",
        "https://example.com:notaport",
    ],
)
def test_an_unusable_origin_stops_the_start_up(value: str, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ALLOW_ORIGINS", value)
    with pytest.raises(SettingsError, match="CORS_ALLOW_ORIGINS"):
        get_settings()


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("", ()),
        (" ", ()),
        (SITE, (SITE,)),
        (f"{SITE},http://localhost:5173", (SITE, "http://localhost:5173")),
        (f" {SITE} , ", (SITE,)),
        ("https://example.com:8443", ("https://example.com:8443",)),
        ("http://127.0.0.1:8080", ("http://127.0.0.1:8080",)),
    ],
)
def test_valid_origins_are_accepted(
    value: str, expected: tuple[str, ...], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("CORS_ALLOW_ORIGINS", value)
    assert get_settings().cors_origins == expected


def test_the_server_is_limited_and_does_not_announce_itself() -> None:
    options = main_module.server_options(get_settings())
    assert options["server_header"] is False
    assert options["h11_max_incomplete_event_size"] == 16 * 1024


# ------------------------------------------------------------------ the image


def dockerfile_text() -> str:
    return (REPO / "app" / "Dockerfile").read_text(encoding="utf-8")


def test_the_image_allows_exactly_the_site_origin() -> None:
    match = re.search(r"^\s*CORS_ALLOW_ORIGINS=(\S+?)\s*\\?$", dockerfile_text(), re.MULTILINE)
    assert match is not None, "the Dockerfile must set CORS_ALLOW_ORIGINS"
    assert match.group(1) == SITE


def test_the_image_sets_no_secret_looking_variable() -> None:
    names = re.findall(r"^\s*(?:ENV\s+)?([A-Z][A-Z0-9_]*)=", dockerfile_text(), re.MULTILINE)
    assert names, "expected ENV settings in the Dockerfile"
    suspicious = [n for n in names if re.search(r"KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL", n)]
    assert suspicious == []


def test_the_docker_context_is_an_allowlist() -> None:
    """Nothing enters the image unless it is listed, so no .env, key or git history can."""
    lines = [
        line.strip()
        for line in (REPO / ".dockerignore").read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    assert lines[0] == "*"
    allowed = [line.removeprefix("!") for line in lines if line.startswith("!")]
    assert allowed, "expected an allowlist"
    risky = [a for a in allowed if re.search(r"\.env|\.git|secret|\.pem|\.key|tfstate", a)]
    assert risky == []

"""Runtime settings, read from the environment when they are asked for (never cached)."""

import os
import re
from dataclasses import dataclass
from pathlib import Path

DEFAULT_VERSION = "0.0.0-dev"
VERSION_PATTERN = re.compile(r"^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$")
GIT_SHA_PATTERN = re.compile(r"^[0-9a-f]{7,40}$")
# An origin is scheme, host and optional port, nothing else: no path, no wildcard. Plain http is
# only for a local development server.
ORIGIN_PATTERN = re.compile(
    r"^(https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?|http://(localhost|127\.0\.0\.1))(:[0-9]{1,5})?$"
)


class SettingsError(ValueError):
    """An environment variable has an unusable value. The service refuses to start."""


@dataclass(frozen=True)
class Settings:
    content_file: Path
    enable_docs: bool
    host: str
    port: int
    # The single source of truth for the running version. The release workflow sets
    # APP_VERSION (from the git tag) and GIT_SHA when it builds the image. The version in
    # pyproject.toml is only a placeholder.
    app_version: str
    git_sha: str | None
    # Websites whose scripts may read the API in a browser (CORS). Empty: no CORS headers at all.
    cors_origins: tuple[str, ...]


def _origins(value: str) -> tuple[str, ...]:
    origins = tuple(part.strip() for part in value.split(",") if part.strip())
    if not all(ORIGIN_PATTERN.fullmatch(origin) for origin in origins):
        raise SettingsError("CORS_ALLOW_ORIGINS has an invalid value")
    return origins


def _checked(name: str, value: str, pattern: re.Pattern[str]) -> str:
    if not pattern.fullmatch(value):
        raise SettingsError(f"{name} has an invalid value")
    return value


def get_settings() -> Settings:
    git_sha = os.environ.get("GIT_SHA")
    return Settings(
        content_file=Path(os.environ.get("CONTENT_FILE", "content.public.json")),
        enable_docs=os.environ.get("ENABLE_DOCS") == "1",
        # Loopback by default. A container sets HOST=0.0.0.0 so other containers can reach it.
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "8080")),
        app_version=_checked(
            "APP_VERSION", os.environ.get("APP_VERSION", DEFAULT_VERSION), VERSION_PATTERN
        ),
        git_sha=_checked("GIT_SHA", git_sha, GIT_SHA_PATTERN) if git_sha else None,
        cors_origins=_origins(os.environ.get("CORS_ALLOW_ORIGINS", "")),
    )

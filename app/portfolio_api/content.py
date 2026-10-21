"""The published content: loading, and the store the API reads it from."""

from pathlib import Path

from pydantic import ValidationError

from portfolio_api.models import Content


class ContentError(RuntimeError):
    """The content file is missing or invalid. The service refuses to start without it."""


def load_content(path: Path) -> Content:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise ContentError(
            f"content file not found: {path}. Build it with `just content-build`."
        ) from exc
    try:
        return Content.model_validate_json(raw)
    except ValidationError as exc:
        raise ContentError(f"content file is invalid: {exc.error_count()} error(s)") from exc


class ContentStore:
    """Holds the validated content between start-up and shutdown (filled by the lifespan)."""

    def __init__(self) -> None:
        self._content: Content | None = None

    def load(self, path: Path) -> None:
        self._content = load_content(path)

    def clear(self) -> None:
        self._content = None

    def get(self) -> Content:
        if self._content is None:
            raise ContentError("content is not loaded: the application has not started")
        return self._content


content_store = ContentStore()


def get_content() -> Content:
    """FastAPI dependency. Tests can override it with `app.dependency_overrides`."""
    return content_store.get()

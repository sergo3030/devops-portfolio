"""Runtime settings, read from the environment when they are asked for (never cached)."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    content_file: Path
    enable_docs: bool
    host: str
    port: int


def get_settings() -> Settings:
    return Settings(
        content_file=Path(os.environ.get("CONTENT_FILE", "content.public.json")),
        enable_docs=os.environ.get("ENABLE_DOCS") == "1",
        # Loopback by default. A container sets HOST=0.0.0.0 so other containers can reach it.
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "8080")),
    )

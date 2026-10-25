"""The application.

Run with `python -m portfolio_api.main` or `uvicorn portfolio_api.main:app --port 8080`.
The content is loaded and validated in the lifespan, when the server starts: a missing or
invalid content file aborts the start-up, so a broken build fails fast instead of serving.
Importing this module reads the environment but does no file I/O.

Environment (see config.py):
  CONTENT_FILE  path of the published content JSON (default: content.public.json)
  ENABLE_DOCS   set to 1 to serve /docs, /redoc and /openapi.json (off by default)
  APP_VERSION   the running version, set by the release build (default: 0.0.0-dev)
  GIT_SHA       the commit the image was built from, set by the release build (optional)
  HOST, PORT    where `python -m portfolio_api.main` listens (default 127.0.0.1:8080)
  CORS_ALLOW_ORIGINS  websites that may read the API in a browser, separated by commas
                (default: none, so no CORS headers; the image sets the site's origin)
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from portfolio_api.config import Settings, get_settings
from portfolio_api.content import content_store
from portfolio_api.routers import content_router, health_router
from portfolio_api.security import ReadOnlyMiddleware, SecurityHeadersMiddleware


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    content_store.load(get_settings().content_file)  # raises ContentError: aborts the start-up
    yield
    content_store.clear()


_settings = get_settings()  # invalid APP_VERSION or GIT_SHA stops the start-up here

app = FastAPI(
    title="portfolio-api",
    version=_settings.app_version,
    lifespan=lifespan,
    docs_url="/docs" if _settings.enable_docs else None,
    redoc_url="/redoc" if _settings.enable_docs else None,
    openapi_url="/openapi.json" if _settings.enable_docs else None,
)
app.include_router(health_router)
app.include_router(content_router)

# The last middleware added is the outermost: the security headers wrap everything, including the
# answers of the other two, and the read-only rule applies before CORS handles a request.
if _settings.cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(_settings.cors_origins),
        allow_methods=["GET", "OPTIONS"],
        allow_headers=["Accept", "Cache-Control"],
        allow_credentials=False,
        max_age=600,
    )
app.add_middleware(ReadOnlyMiddleware)
app.add_middleware(SecurityHeadersMiddleware)


def server_options(settings: Settings) -> dict[str, Any]:
    """How uvicorn runs the app: no `server: uvicorn` banner, and a request that trickles in is cut
    off at 16 KB. A request that arrives in one piece is limited by ReadOnlyMiddleware instead."""
    return {
        "host": settings.host,
        "port": settings.port,
        "log_level": "warning",
        "server_header": False,
        "h11_max_incomplete_event_size": 16 * 1024,
    }


if __name__ == "__main__":
    uvicorn.run("portfolio_api.main:app", **server_options(get_settings()))

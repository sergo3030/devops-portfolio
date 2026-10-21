"""The application.

Run with `python -m portfolio_api.main` or `uvicorn portfolio_api.main:app --port 8080`.
The content is loaded and validated in the lifespan, when the server starts: a missing or
invalid content file aborts the start-up, so a broken build fails fast instead of serving.
Importing this module reads the environment but does no file I/O.

Environment (see config.py):
  CONTENT_FILE  path of the published content JSON (default: content.public.json)
  ENABLE_DOCS   set to 1 to serve /docs, /redoc and /openapi.json (off by default)
  HOST, PORT    where `python -m portfolio_api.main` listens (default 127.0.0.1:8080)
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI

from portfolio_api.config import get_settings
from portfolio_api.content import content_store
from portfolio_api.routers import content_router, health_router


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    content_store.load(get_settings().content_file)  # raises ContentError: aborts the start-up
    yield
    content_store.clear()


_docs = get_settings().enable_docs

app = FastAPI(
    title="portfolio-api",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs" if _docs else None,
    redoc_url="/redoc" if _docs else None,
    openapi_url="/openapi.json" if _docs else None,
)
app.include_router(health_router)
app.include_router(content_router)


if __name__ == "__main__":
    settings = get_settings()
    uvicorn.run(
        "portfolio_api.main:app", host=settings.host, port=settings.port, log_level="warning"
    )

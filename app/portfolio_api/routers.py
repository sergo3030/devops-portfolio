"""The API routes, grouped in routers that `main.py` attaches to the app."""

from typing import Annotated

from fastapi import APIRouter, Depends, Response

from portfolio_api.content import get_content
from portfolio_api.models import Content

CACHE_CONTROL = "public, max-age=300"

health_router = APIRouter(tags=["Health"])
content_router = APIRouter(tags=["Content"])


@health_router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@content_router.get("/content", response_model=Content)
def read_content(response: Response, content: Annotated[Content, Depends(get_content)]) -> Content:
    response.headers["Cache-Control"] = CACHE_CONTROL
    return content

"""Two small ASGI middlewares that harden every response of the API.

They are plain ASGI (no framework magic), so they also wrap the answers of the CORS middleware
and the errors of the framework, and they are easy to test on their own.
"""

from starlette.datastructures import MutableHeaders
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

# The API returns JSON and nothing a browser should ever render, frame or sniff.
SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
    "Strict-Transport-Security": "max-age=31536000",
}

# The API only reads. Any other method, or any request that carries a body, is refused.
ALLOWED_METHODS = ("GET", "OPTIONS")

# Real requests to this API are a few hundred bytes. Browsers send at most a few KB of headers.
MAX_HEADER_BYTES = 16 * 1024
MAX_URL_BYTES = 2048


class SecurityHeadersMiddleware:
    """Adds the security headers to every response, errors included.

    A response without its own Cache-Control (errors, /health) must not be cached.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                for name, value in SECURITY_HEADERS.items():
                    headers[name] = value
                if "cache-control" not in headers:
                    headers["Cache-Control"] = "no-store"
            await send(message)

        await self.app(scope, receive, send_with_headers)


class ReadOnlyMiddleware:
    """Refuses requests this read-only service has no use for, before anything handles them.

    - a method other than GET and OPTIONS: 405
    - a body (a Content-Length other than 0, or a Transfer-Encoding): 413
    - all headers together larger than 16 KB: 431
    - a URL (path and query) longer than 2048 bytes: 414

    Nothing is read, parsed or stored from a refused request. The header and URL limits are checked
    here because uvicorn's own limit only applies to a request that arrives in pieces.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        header_bytes = sum(len(name) + len(value) + 4 for name, value in scope["headers"])
        if header_bytes > MAX_HEADER_BYTES:
            await JSONResponse({"detail": "Request headers too large"}, status_code=431)(
                scope, receive, send
            )
            return
        if len(scope.get("raw_path") or b"") + len(scope.get("query_string", b"")) > MAX_URL_BYTES:
            await JSONResponse({"detail": "URL too long"}, status_code=414)(scope, receive, send)
            return

        if scope["method"] not in ALLOWED_METHODS:
            response = JSONResponse(
                {"detail": "Method Not Allowed"},
                status_code=405,
                headers={"Allow": ", ".join(ALLOWED_METHODS)},
            )
            await response(scope, receive, send)
            return

        headers = {name.lower(): value for name, value in scope["headers"]}
        if (
            headers.get(b"content-length", b"0") not in (b"", b"0")
            or b"transfer-encoding" in headers
        ):
            await JSONResponse({"detail": "Request body not allowed"}, status_code=413)(
                scope, receive, send
            )
            return

        await self.app(scope, receive, send)

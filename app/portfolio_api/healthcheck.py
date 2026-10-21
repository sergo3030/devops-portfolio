"""Container health check: exit 0 when GET /health answers 200, exit 1 otherwise.

Used by the Dockerfile HEALTHCHECK, so the image needs no curl. It reads the port from the same
settings as the app, so a changed PORT cannot silently break it. Lambda ignores HEALTHCHECK.
"""

import sys
import urllib.request

from portfolio_api.config import get_settings


def check(port: int, timeout: float = 2.0) -> bool:
    url = f"http://127.0.0.1:{port}/health"
    try:
        # A fixed loopback http URL, never user input.
        with urllib.request.urlopen(url, timeout=timeout) as response:  # noqa: S310
            return bool(response.status == 200)
    except OSError:  # refused, timed out, or an HTTP error status (HTTPError is an OSError)
        return False


def main() -> int:
    return 0 if check(get_settings().port) else 1


if __name__ == "__main__":
    sys.exit(main())

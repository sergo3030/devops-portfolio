"""Checks that the deployed API answers and runs the commit that was deployed.

    python3 scripts/verify_deploy.py <base-url> <expected-commit> [attempts] [seconds-between]

It calls `<base-url>/health` and requires status ok and a `git_sha` equal to the commit. A cold
Lambda needs several seconds, and a function that was just updated can answer from the old image
for a moment, so a failing attempt is repeated (6 times, 10 s apart by default) before the check
gives up. Standard library only: it runs on the plain runner.
"""

import json
import re
import sys
import time
import urllib.error
import urllib.request
from typing import Any

COMMIT = re.compile(r"^[0-9a-f]{40}$")


def check_once(base_url: str, expected: str, timeout: float) -> str | None:
    """None when the API is healthy and runs `expected`, otherwise what is wrong."""
    request = urllib.request.Request(  # noqa: S310 - the scheme is checked in main()
        base_url.rstrip("/") + "/health", headers={"Accept": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
            if response.status != 200:
                return f"/health answered {response.status}"
            body: Any = json.load(response)
    except (urllib.error.URLError, TimeoutError, ValueError, OSError) as error:
        return f"/health did not answer: {error}"
    if not isinstance(body, dict) or body.get("status") != "ok":
        return f"/health did not report status ok: {body!r}"
    if body.get("git_sha") != expected:
        return f"the API runs commit {body.get('git_sha')!r}, expected {expected!r}"
    return None


def main(argv: list[str]) -> int:
    if not 2 <= len(argv) <= 4:
        print(
            "usage: verify_deploy.py <base-url> <expected-commit> [attempts] [seconds]",
            file=sys.stderr,
        )
        return 2
    base_url, expected = argv[0], argv[1]
    attempts = int(argv[2]) if len(argv) > 2 else 6
    pause = float(argv[3]) if len(argv) > 3 else 10.0

    if not base_url.startswith(("https://", "http://127.0.0.1", "http://localhost")):
        print("the URL must be https (or a local test server)", file=sys.stderr)
        return 2
    if not COMMIT.match(expected):
        print(f"expected commit {expected!r} is not a full 40-character hash", file=sys.stderr)
        return 2

    for attempt in range(1, attempts + 1):
        problem = check_once(base_url, expected, timeout=30.0)
        if problem is None:
            print(f"deploy verified: the API is healthy and runs {expected[:7]}")
            return 0
        print(f"attempt {attempt}/{attempts}: {problem}", file=sys.stderr)
        if attempt < attempts:
            time.sleep(pause)
    print("deploy did NOT verify", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

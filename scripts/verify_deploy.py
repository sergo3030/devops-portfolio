"""Checks that the deployed API answers and runs the commit and version that were deployed.

    python3 scripts/verify_deploy.py <base-url> <commit> <version> [attempts] [seconds-between]

It calls `<base-url>/health` and requires status ok, a `git_sha` equal to the commit and a
`version` equal to the version (0.0.0-dev for a development build, x.y.z for a release). A cold
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
VERSION = re.compile(r"^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$")


def check_once(base_url: str, commit: str, version: str, timeout: float) -> str | None:
    """None when the API is healthy and runs `commit` and `version`, otherwise what is wrong."""
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
    if body.get("git_sha") != commit:
        return f"the API runs commit {body.get('git_sha')!r}, expected {commit!r}"
    if body.get("version") != version:
        return f"the API reports version {body.get('version')!r}, expected {version!r}"
    return None


def main(argv: list[str]) -> int:
    if not 3 <= len(argv) <= 5:
        print(
            "usage: verify_deploy.py <base-url> <commit> <version> [attempts] [seconds]",
            file=sys.stderr,
        )
        return 2
    base_url, commit, version = argv[0], argv[1], argv[2]
    attempts = int(argv[3]) if len(argv) > 3 else 6
    pause = float(argv[4]) if len(argv) > 4 else 10.0

    if not base_url.startswith(("https://", "http://127.0.0.1", "http://localhost")):
        print("the URL must be https (or a local test server)", file=sys.stderr)
        return 2
    if not COMMIT.match(commit):
        print(f"expected commit {commit!r} is not a full 40-character hash", file=sys.stderr)
        return 2
    if not VERSION.match(version):
        print(f"expected version {version!r} is not a valid version", file=sys.stderr)
        return 2

    for attempt in range(1, attempts + 1):
        problem = check_once(base_url, commit, version, timeout=30.0)
        if problem is None:
            print(f"deploy verified: the API is healthy and runs {version} ({commit[:7]})")
            return 0
        print(f"attempt {attempt}/{attempts}: {problem}", file=sys.stderr)
        if attempt < attempts:
            time.sleep(pause)
    print("deploy did NOT verify", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

"""Counts the consecutive green runs of the `ci` workflow on main, newest first.

    python3 scripts/ci_streak.py [--limit N] [--require N] [--json FILE]

A run that was cancelled (superseded by a newer push) or is still running does not break the
streak and is not counted; a failure ends it. It reads the runs with `gh run list`, or from a JSON
file with the same fields (used by the tests). With --require N it exits 1 when the streak is
shorter than N. Standard library only.
"""

import argparse
import json
import subprocess
import sys
from typing import Any


def streak(runs: list[dict[str, Any]]) -> int:
    """`runs` newest first, each with a `conclusion`: success, failure, cancelled or empty."""
    count = 0
    for run in runs:
        conclusion = run.get("conclusion") or ""
        if conclusion == "success":
            count += 1
        elif conclusion in ("", "cancelled", "skipped", "neutral"):
            continue
        else:
            break
    return count


def load(limit: int, json_file: str | None) -> list[dict[str, Any]]:
    if json_file:
        with open(json_file, encoding="utf-8") as handle:
            data: list[dict[str, Any]] = json.load(handle)
        return data
    command = [  # noqa: S607 - `gh` is looked up on PATH on purpose
        "gh",
        "run",
        "list",
        "--workflow",
        "ci.yml",
        "--branch",
        "main",
        "--event",
        "push",
        "--limit",
        str(limit),
        "--json",
        "conclusion,headSha,createdAt",
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=True)  # noqa: S603
    parsed: list[dict[str, Any]] = json.loads(result.stdout)
    return parsed


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else "")
    parser.add_argument("--limit", type=int, default=60)
    parser.add_argument("--require", type=int, default=0)
    parser.add_argument("--json", dest="json_file")
    args = parser.parse_args(argv)

    count = streak(load(args.limit, args.json_file))
    print(f"{count} consecutive green ci runs on main")
    if args.require and count < args.require:
        print(f"fewer than the {args.require} required", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

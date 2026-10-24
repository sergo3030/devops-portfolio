"""Checks that a plan of the prod root only swaps the Lambda image, before it is applied.

    python3 scripts/check_deploy_plan.py <plan.json> <image-digest>

`plan.json` is `tofu show -json <saved plan>`. The deploy workflow applies a plan only if it
passes, so a deploy by digest can never destroy, create or reconfigure anything else by accident.
Anything unusual (a destroy, a new resource, a changed memory size, a different digest) fails
and says to apply by hand. Standard library only: it runs on the plain runner.

Result: exit 0 and `changes=true` or `changes=false` on $GITHUB_OUTPUT (stdout when unset), or
exit 1 and the reasons on stderr.
"""

import json
import os
import re
import sys
from typing import Any

FUNCTION = "aws_lambda_function.api[0]"
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
QUIET_ACTIONS = ({"no-op"}, {"read"})


def problems(plan: dict[str, Any], digest: str) -> tuple[list[str], bool]:
    """The reasons the plan is not an image-only update, and whether it changes anything."""
    found: list[str] = []
    changes = False

    if not DIGEST.match(digest):
        return [f"the digest {digest!r} is not sha256:<64 hex characters>"], False

    for resource in plan.get("resource_changes", []):
        address = str(resource.get("address", "?"))
        change = resource.get("change", {})
        actions = set(change.get("actions", []))
        if actions in QUIET_ACTIONS:
            continue
        changes = True

        if address != FUNCTION:
            found.append(
                f"{address} would change ({', '.join(sorted(actions))}); only {FUNCTION} may"
            )
            continue
        if actions != {"update"}:
            what = ", ".join(sorted(actions))
            found.append(f"{address} would be {what}; only an in-place update is allowed")
            continue

        before: dict[str, Any] = change.get("before") or {}
        after: dict[str, Any] = change.get("after") or {}
        # Attributes the provider computes after the apply (version, hashes, timestamps) are not
        # inputs, so they do not count as a change.
        computed: dict[str, Any] = change.get("after_unknown") or {}
        differing = {
            key
            for key in set(before) | set(after)
            if before.get(key) != after.get(key) and not computed.get(key)
        }
        if differing != {"image_uri"}:
            names = ", ".join(sorted(differing)) or "nothing but computed values"
            found.append(f"{address} changes {names}; only image_uri may")
            continue
        new_image = str(after.get("image_uri", ""))
        if not new_image.endswith(f"@{digest}"):
            found.append(
                f"{address} would run {new_image!r}, which is not the approved digest {digest}"
            )

    return found, changes


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: check_deploy_plan.py <plan.json> <image-digest>", file=sys.stderr)
        return 2
    try:
        with open(argv[0], encoding="utf-8") as handle:
            plan = json.load(handle)
    except (OSError, ValueError) as error:
        print(f"cannot read the plan: {error}", file=sys.stderr)
        return 1
    if not isinstance(plan, dict):
        print("the plan JSON is not an object", file=sys.stderr)
        return 1

    found, changes = problems(plan, argv[1])
    if found:
        print(
            "This is not an image-only deploy. Apply it by hand after reading the plan:",
            file=sys.stderr,
        )
        for line in found:
            print(f"  - {line}", file=sys.stderr)
        return 1

    out = os.environ.get("GITHUB_OUTPUT")
    line = f"changes={'true' if changes else 'false'}\n"
    if out:
        with open(out, "a", encoding="utf-8") as handle:
            handle.write(line)
    else:
        sys.stdout.write(line)
    print(
        "the plan only swaps the Lambda image"
        if changes
        else "no changes: the digest is already deployed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

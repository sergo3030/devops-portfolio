"""Export the JSON Schema of the published content.

That schema is the contract between the API and the web app. It is generated from the Pydantic
models, committed as `content/schema/published.schema.json`, and a test fails when the committed
file is stale. The web app generates its TypeScript types from it, so one change to a model
flows to the UI and cannot drift.

    python -m portfolio_api.schema_export              # rewrite the committed file
    python -m portfolio_api.schema_export --output X   # write somewhere else
"""

import argparse
import json
import sys
from pathlib import Path

from portfolio_api.models import Content

DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[2] / "content" / "schema" / "published.schema.json"
)


def render() -> str:
    """The schema as text, with stable key order so diffs stay small."""
    return json.dumps(Content.model_json_schema(), indent=2, sort_keys=True) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Export the published content schema.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args(argv)
    args.output.write_text(render(), encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""The committed JSON Schema of the published content must match the Pydantic models."""

import json
from pathlib import Path

from portfolio_api.schema_export import DEFAULT_OUTPUT, main, render

HINT = (
    "Run `python -m portfolio_api.schema_export` (or `just schema-export`) and commit the result."
)


def test_committed_schema_is_current() -> None:
    assert DEFAULT_OUTPUT.read_text(encoding="utf-8") == render(), HINT


def test_schema_forbids_unknown_fields_everywhere() -> None:
    schema = json.loads(render())
    models = [schema, *schema["$defs"].values()]
    assert all(model.get("additionalProperties") is False for model in models)


def test_export_writes_the_rendered_schema(tmp_path: Path) -> None:
    target = tmp_path / "out.json"
    assert main(["--output", str(target)]) == 0
    assert target.read_text(encoding="utf-8") == render()

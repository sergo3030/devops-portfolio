"""Placeholder so the CI skeleton has something to run. Replaced in task 10."""

import tomllib
from pathlib import Path


def test_project_metadata_loads() -> None:
    data = tomllib.loads((Path(__file__).parents[1] / "pyproject.toml").read_text())
    assert data["project"]["name"] == "portfolio-api"

"""Tests for the CI streak counter: scripts/ci_streak.py."""

import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

import pytest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ci_streak", REPO / "scripts" / "ci_streak.py")
assert spec is not None and spec.loader is not None
ci_streak = importlib.util.module_from_spec(spec)
sys.modules["ci_streak"] = ci_streak
spec.loader.exec_module(ci_streak)


def runs(*conclusions: str) -> list[dict[str, Any]]:
    return [{"conclusion": c} for c in conclusions]


@pytest.mark.parametrize(
    ("conclusions", "expected"),
    [
        ((), 0),
        (("success",), 1),
        (("success", "success", "failure", "success"), 2),
        (("failure", "success"), 0),
        (("success", "cancelled", "success"), 2),  # a superseded run neither breaks nor counts
        (("", "success", "success"), 2),  # a run still in progress is skipped
        (("success", "skipped", "success", "failure"), 2),
        (("success", "timed_out", "success"), 1),  # anything else that is not green ends it
    ],
)
def test_the_streak_counts_green_runs_until_the_first_failure(
    conclusions: tuple[str, ...], expected: int
) -> None:
    assert ci_streak.streak(runs(*conclusions)) == expected


def test_a_missing_conclusion_is_treated_as_not_finished() -> None:
    assert ci_streak.streak([{}, {"conclusion": "success"}]) == 1


def test_the_command_prints_the_count(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    file = tmp_path / "runs.json"
    file.write_text(json.dumps(runs("success", "success", "failure")), encoding="utf-8")
    assert ci_streak.main(["--json", str(file)]) == 0
    assert capsys.readouterr().out.strip() == "2 consecutive green ci runs on main"


def test_require_fails_a_short_streak(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    file = tmp_path / "runs.json"
    file.write_text(json.dumps(runs(*["success"] * 4 + ["failure"])), encoding="utf-8")
    assert ci_streak.main(["--json", str(file), "--require", "10"]) == 1
    assert "fewer than the 10 required" in capsys.readouterr().err
    assert ci_streak.main(["--json", str(file), "--require", "4"]) == 0

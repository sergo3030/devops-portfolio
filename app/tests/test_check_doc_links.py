"""Tests for the documentation link check: scripts/check_doc_links.py."""

import importlib.util
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "check_doc_links", REPO / "scripts" / "check_doc_links.py"
)
assert spec is not None and spec.loader is not None
links = importlib.util.module_from_spec(spec)
sys.modules["check_doc_links"] = links
spec.loader.exec_module(links)


def tree(tmp_path: Path, files: dict[str, str]) -> Path:
    for name, content in files.items():
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    return tmp_path


def run(root: Path) -> int:
    return int(links.main([str(root)]))


def test_the_real_documentation_has_no_broken_link() -> None:
    assert run(REPO) == 0


def test_working_links_pass(tmp_path: Path) -> None:
    root = tree(
        tmp_path,
        {
            "README.md": "[a](docs/a.md) [b](docs/a.md#the-heading) [c](docs) [d](#top)\n# Top\n",
            "docs/a.md": "# A\n## The heading\n[back](../README.md)\n",
        },
    )
    assert run(root) == 0


def test_a_missing_file_fails(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = tree(tmp_path, {"README.md": "[x](docs/missing.md)\n", "docs/a.md": "# A\n"})
    assert run(root) == 1
    assert "docs/missing.md" in capsys.readouterr().err


def test_a_missing_heading_fails(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = tree(tmp_path, {"README.md": "[x](docs/a.md#nope)\n", "docs/a.md": "# A\n"})
    assert run(root) == 1
    assert "has no heading 'nope'" in capsys.readouterr().err


def test_a_broken_link_inside_docs_is_found_relative_to_that_file(tmp_path: Path) -> None:
    root = tree(tmp_path, {"README.md": "# R\n", "docs/a.md": "[x](b.md)\n", "docs/b.md": "# B\n"})
    assert run(root) == 0
    (root / "docs" / "b.md").unlink()
    assert run(root) == 1


@pytest.mark.parametrize(
    ("heading", "anchor"),
    [
        ("Teardown: three levels (task 18a, D48)", "teardown-three-levels-task-18a-d48"),
        (
            "Cost guards, and how each was tested (task 18, D47)",
            "cost-guards-and-how-each-was-tested-task-18-d47",
        ),
        ("Why `uv` and not pip?", "why-uv-and-not-pip"),
        ("Quick start (Windows, Git Bash)", "quick-start-windows-git-bash"),
    ],
)
def test_headings_make_the_anchors_github_makes(tmp_path: Path, heading: str, anchor: str) -> None:
    root = tree(
        tmp_path, {"README.md": f"[x](docs/a.md#{anchor})\n", "docs/a.md": f"# {heading}\n"}
    )
    assert run(root) == 0


def test_repeated_headings_are_numbered(tmp_path: Path) -> None:
    root = tree(
        tmp_path,
        {"README.md": "[x](docs/a.md#notes-1)\n", "docs/a.md": "# Notes\n## Notes\n"},
    )
    assert run(root) == 0
    (root / "README.md").write_text("[x](docs/a.md#notes-2)\n", encoding="utf-8")
    assert run(root) == 1


def test_other_sites_code_blocks_and_inline_code_are_not_checked(tmp_path: Path) -> None:
    root = tree(
        tmp_path,
        {
            "README.md": (
                "[site](https://example.com/x) [mail](mailto:a@example.com)\n"
                "```\n[nope](missing.md)\n```\n"
                "and `[nope](missing.md)` inline\n"
            )
        },
    )
    assert run(root) == 0


def test_images_and_reference_definitions_are_checked(tmp_path: Path) -> None:
    root = tree(tmp_path, {"README.md": "![d](docs/diagram.png)\n"})
    assert run(root) == 1
    root = tree(tmp_path / "second", {"README.md": "[ref]: docs/missing.md\n"})
    assert run(root) == 1


def test_an_empty_tree_is_an_error(tmp_path: Path) -> None:
    assert run(tmp_path) == 2

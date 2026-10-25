"""Tests for scripts/check_content.py: planted violations must fail, clean content must pass."""

import copy
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

import pytest
import yaml

REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "check_content", REPO / "scripts" / "check_content.py"
)
assert SPEC and SPEC.loader
check_content = importlib.util.module_from_spec(SPEC)
sys.modules["check_content"] = check_content
SPEC.loader.exec_module(check_content)

SCHEMA = REPO / "content" / "schema" / "content.schema.json"
ALLOWED_NUMBERS = REPO / "content" / "allowed-numbers.txt"


def line(text: str, approved: bool = True) -> dict[str, Any]:
    return {"text": text, "approved": approved}


def clean_content() -> dict[str, Any]:
    return {
        "version": 1,
        "profile": {
            "name": line("Test Person"),
            "title": line("DevOps Engineer"),
            "summary": line("Builds platforms with Kubernetes and Python."),
            "country": line("Israel"),
        },
        "links": [{"label": "GitHub", "url": "https://github.com/example", "approved": True}],
        "skills": [{"category": "Containers", "items": ["Kubernetes", "Helm"], "approved": True}],
        "experience": [
            {
                "employer": "Example Corp",
                "role": "DevOps Engineer",
                "start": "2024-03",
                "end": "present",
                "approved": True,
                "bullets": [line("Upgraded the cluster from 1.31 to 1.35 between 2018-2022.")],
            }
        ],
        "case_studies": [
            {
                "id": "gateway-migration",
                "title": "Gateway API migration",
                "employer_approval": "granted",
                "approved": True,
                "summary": line("Replaced the ingress controller."),
                "sections": [
                    {
                        "heading": "Context",
                        "approved": True,
                        "paragraphs": [line("Used SHA-256 digests.")],
                    }
                ],
            }
        ],
        "languages": [{"name": "English", "approved": True}],
    }


def run(
    tmp_path: Path,
    content: dict[str, Any],
    denylist: list[str] | None = None,
    allow_missing: bool = False,
    build: bool = False,
) -> tuple[int, str, Path]:
    content_path = tmp_path / "content.yaml"
    content_path.write_text(yaml.safe_dump(content, allow_unicode=True), encoding="utf-8")
    args = [
        "--content",
        str(content_path),
        "--schema",
        str(SCHEMA),
        "--allowed-numbers",
        str(ALLOWED_NUMBERS),
    ]
    denylist_path = tmp_path / "denylist.txt"
    if denylist is None:
        args += ["--denylist", str(tmp_path / "missing.txt")]
    else:
        denylist_path.write_text("\n".join(denylist) + "\n", encoding="utf-8")
        args += ["--denylist", str(denylist_path)]
    if allow_missing:
        args.append("--allow-missing-denylist")
    out_path = tmp_path / "public.json"
    if build:
        args += ["--build", str(out_path)]
    import contextlib
    import io

    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        code = check_content.main(args)
    return code, err.getvalue(), out_path


def test_clean_content_passes(tmp_path: Path) -> None:
    code, err, _ = run(tmp_path, clean_content(), denylist=["Zorgon"])
    assert code == 0, err


FAKE_KEY = "AKIA" + "ABCDEFGHIJKLMNOP"  # assembled at run time: no literal key in the source

PLANTED = [
    ("ticket id", "See DO-1234 for details."),
    ("email address", "Write to alice@example.com."),
    ("phone number", "Call +972 54 123 4567."),
    ("ip address", "Runs on 10.0.0.12."),
    ("internal host name", "Deployed on build.corp today."),
    ("file path", "Stored in C:\\Users\\someone\\notes."),
    ("cloud account id", "Account 123456789012 is used."),
    ("key material", f"Key {FAKE_KEY} was used."),
    ("url outside the allowlist", "See https://internal.example.com/wiki."),
    ("number not on the CV allowlist", "Closed 293 tickets."),
]


# Explicit IDs: the planted strings must never end up in test names, caches or CI logs.
@pytest.mark.parametrize(("rule", "text"), PLANTED, ids=[rule for rule, _ in PLANTED])
def test_planted_leak_fails(tmp_path: Path, rule: str, text: str) -> None:
    content = clean_content()
    content["profile"]["summary"] = line(text)
    code, err, _ = run(tmp_path, content, denylist=["Zorgon"])
    assert code == 1
    assert rule in err
    assert "profile.summary" in err


def test_leak_in_an_unapproved_line_still_fails(tmp_path: Path) -> None:
    content = clean_content()
    content["profile"]["summary"] = line("See DO-1234.", approved=False)
    code, _, _ = run(tmp_path, content, denylist=["Zorgon"])
    assert code == 1


def test_denylist_term_fails_without_echoing_it(tmp_path: Path) -> None:
    content = clean_content()
    content["profile"]["summary"] = line("Worked on the Zorgon service.")
    code, err, _ = run(tmp_path, content, denylist=["# comment", "Zorgon"])
    assert code == 1
    assert "private denylist entry #1" in err
    assert "Zorgon" not in err


def test_denylist_regex_entry_fails(tmp_path: Path) -> None:
    content = clean_content()
    content["profile"]["summary"] = line("Project Falcon-7 shipped.")
    code, err, _ = run(tmp_path, content, denylist=[r"re:Falcon-\d"])
    assert code == 1
    assert "denylist" in err


def test_denylist_matches_whole_words_only(tmp_path: Path) -> None:
    content = clean_content()
    content["profile"]["summary"] = line("Zorgonian cuisine is not a leak.")
    code, _, _ = run(tmp_path, content, denylist=["Zorgon"])
    assert code == 0


def test_missing_denylist_fails_unless_ci_flag(tmp_path: Path) -> None:
    code, err, _ = run(tmp_path, clean_content(), denylist=None)
    assert code == 1
    assert "denylist file is missing" in err
    code_ci, _, _ = run(tmp_path, clean_content(), denylist=None, allow_missing=True)
    assert code_ci == 0


def test_schema_violations_fail(tmp_path: Path) -> None:
    missing = clean_content()
    del missing["skills"]
    code, err, _ = run(tmp_path, missing, denylist=["Zorgon"])
    assert code == 1
    assert "schema:" in err

    extra = clean_content()
    extra["profile"]["phone"] = line("+972 54 123 4567")
    code, err, _ = run(tmp_path, extra, denylist=["Zorgon"])
    assert code == 1
    assert "schema:" in err


def test_link_outside_the_allowed_sites_fails_the_schema(tmp_path: Path) -> None:
    content = clean_content()
    content["links"][0]["url"] = "https://example.com/someone"
    code, err, _ = run(tmp_path, content, denylist=["Zorgon"])
    assert code == 1
    assert "schema:" in err


def test_build_contains_approved_lines_only(tmp_path: Path) -> None:
    content = clean_content()
    content["profile"]["summary"] = line("Not reviewed yet.", approved=False)
    content["experience"][0]["bullets"].append(line("Second bullet, not approved.", approved=False))
    content["skills"].append({"category": "Draft", "items": ["Something"], "approved": False})
    code, err, out = run(tmp_path, content, denylist=["Zorgon"], build=True)
    assert code == 0, err
    public = json.loads(out.read_text(encoding="utf-8"))
    assert "summary" not in public["profile"]
    assert public["profile"]["name"] == "Test Person"
    assert len(public["experience"][0]["bullets"]) == 1
    assert [s["category"] for s in public["skills"]] == ["Containers"]
    assert "approved" not in json.dumps(public)


def test_pending_employer_approval_is_never_published(tmp_path: Path) -> None:
    content = clean_content()
    pending = copy.deepcopy(content["case_studies"][0])
    pending["id"] = "pending-study"
    pending["employer_approval"] = "pending"
    content["case_studies"].append(pending)
    code, err, out = run(tmp_path, content, denylist=["Zorgon"], build=True)
    assert code == 0, err
    public = json.loads(out.read_text(encoding="utf-8"))
    assert [s["id"] for s in public["case_studies"]] == ["gateway-migration"]


def about_block() -> dict[str, Any]:
    return {
        "title": line("About this project"),
        "sections": [
            {
                "heading": "Why",
                "approved": True,
                "paragraphs": [line("A reviewed paragraph."), line("A draft.", approved=False)],
            },
            {
                "heading": "Draft section",
                "approved": False,
                "paragraphs": [line("Not reviewed yet.")],
            },
            {
                "heading": "Only drafts inside",
                "approved": True,
                "paragraphs": [line("Still a draft.", approved=False)],
            },
        ],
    }


def test_about_is_published_with_approved_parts_only(tmp_path: Path) -> None:
    content = clean_content()
    content["about"] = about_block()
    code, err, out = run(tmp_path, content, denylist=["Zorgon"], build=True)
    assert code == 0, err
    public = json.loads(out.read_text(encoding="utf-8"))
    assert public["about"] == {
        "title": "About this project",
        "sections": [{"heading": "Why", "paragraphs": ["A reviewed paragraph."]}],
    }
    assert "approved" not in json.dumps(public)


def test_an_unapproved_about_title_is_left_out(tmp_path: Path) -> None:
    content = clean_content()
    content["about"] = about_block()
    content["about"]["title"] = line("About this project", approved=False)
    code, err, out = run(tmp_path, content, denylist=["Zorgon"], build=True)
    assert code == 0, err
    assert "title" not in json.loads(out.read_text(encoding="utf-8"))["about"]


def test_an_about_with_nothing_approved_is_not_published(tmp_path: Path) -> None:
    content = clean_content()
    content["about"] = about_block()
    for section in content["about"]["sections"]:
        section["approved"] = False
    code, err, out = run(tmp_path, content, denylist=["Zorgon"], build=True)
    assert code == 0, err
    assert "about" not in json.loads(out.read_text(encoding="utf-8"))


def test_content_without_an_about_still_builds(tmp_path: Path) -> None:
    code, err, out = run(tmp_path, clean_content(), denylist=["Zorgon"], build=True)
    assert code == 0, err
    assert "about" not in json.loads(out.read_text(encoding="utf-8"))


@pytest.mark.parametrize(("rule", "text"), PLANTED, ids=[rule for rule, _ in PLANTED])
def test_planted_leak_in_about_fails_even_in_a_draft(tmp_path: Path, rule: str, text: str) -> None:
    content = clean_content()
    content["about"] = about_block()
    content["about"]["sections"][1]["paragraphs"][0] = line(text, approved=False)
    code, err, _ = run(tmp_path, content, denylist=["Zorgon"])
    assert code == 1
    assert rule in err
    assert "about.sections" in err


def test_a_denylist_term_in_about_fails(tmp_path: Path) -> None:
    content = clean_content()
    content["about"] = about_block()
    content["about"]["sections"][0]["paragraphs"][0] = line("Built at Zorgon last year.")
    code, err, _ = run(tmp_path, content, denylist=["Zorgon"])
    assert code == 1
    assert "Zorgon" not in err


def test_an_about_without_a_title_fails_the_schema(tmp_path: Path) -> None:
    content = clean_content()
    content["about"] = about_block()
    del content["about"]["title"]
    code, err, _ = run(tmp_path, content, denylist=["Zorgon"])
    assert code == 1
    assert "schema:" in err


def test_repository_content_passes_the_generic_checks() -> None:
    """The committed content must pass everything except the private denylist (CI has none)."""
    code = check_content.main(
        [
            "--content",
            str(REPO / "content" / "content.yaml"),
            "--schema",
            str(SCHEMA),
            "--allowed-numbers",
            str(ALLOWED_NUMBERS),
            "--allow-missing-denylist",
        ]
    )
    assert code == 0

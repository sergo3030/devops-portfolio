#!/usr/bin/env python3
"""Check the public-safe portfolio content and build the published subset.

Checks, in order (all must pass):
1. the content validates against content/schema/content.schema.json
2. generic leak patterns: ticket IDs, emails, phone numbers, IPs, internal host names,
   URLs outside an allowlist, file paths, account IDs, key material
3. numbers: only numbers listed in content/allowed-numbers.txt (all already on the
   owner's current CV) and plain years are allowed
4. the private denylist (a file OUTSIDE the repository, so CI cannot see it): the
   check runs locally and in the pre-commit hook

The checks look at every line, approved or not, so a draft can never hold a leak.
`--build` writes the published subset: approved lines only, and case studies only when
they are approved and the employer approval is `granted`.

Findings name the path and the rule, never the matched text or the denylist entry.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

ALLOWED_URL_HOSTS = {"linkedin.com", "www.linkedin.com", "github.com", "www.github.com"}

# Keys whose values are structured data, not prose: the schema checks them instead.
SKIP_KEYS = {"version", "url", "start", "end", "id", "employer_approval"}

# Look like ticket IDs but are ordinary technical terms.
TICKET_EXCEPTIONS = re.compile(
    r"^(SHA|UTF|ISO|TLS|IEEE|RFC|CIS|NIST|AES|RSA|ECC|MD|X|CVE|SP|IR)-\d+$"
)
YEAR_RANGE = re.compile(r"^(19|20)\d{2}\s*[-–]\s*(19|20)\d{2}$")
YEAR = re.compile(r"^20\d{2}$")

GENERIC_PATTERNS: dict[str, re.Pattern[str]] = {
    "ticket id": re.compile(r"\b[A-Z][A-Z0-9]{1,9}-\d{1,6}\b"),
    "email address": re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"),
    "phone number": re.compile(r"(?<![\w.])\+?\d[\d\s().-]{7,}\d(?![\w])"),
    "ip address": re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"),
    "internal host name": re.compile(
        r"\b[\w-]+(?:\.[\w-]+)*\.(?:internal|local|corp|lan|intra)\b", re.IGNORECASE
    ),
    "file path": re.compile(r"(?:[A-Za-z]:\\|/(?:home|Users|etc|var|opt)/)"),
    "cloud account id": re.compile(r"(?<!\d)\d{12}(?!\d)"),
    "key material": re.compile(
        r"AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----"
    ),
}
URL_PATTERN = re.compile(r"(?:https?://|www\.)[^\s)>\"']+", re.IGNORECASE)
# A number glued to a name with a hyphen (SHA-256, X-509) is part of that name.
NUMBER_PATTERN = re.compile(r"(?<![\w.])(?<![A-Za-z]-)\d+(?:\.\d+)*\+?(?![\w])")


def walk_strings(node: Any, path: str = "") -> Iterator[tuple[str, str]]:
    """Yield (path, text) for every prose string in the content."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key in SKIP_KEYS:
                continue
            yield from walk_strings(value, f"{path}.{key}" if path else str(key))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_strings(value, f"{path}[{index}]")
    elif isinstance(node, str):
        yield path, node


def schema_findings(content: Any, schema: dict[str, Any]) -> list[str]:
    validator = Draft202012Validator(schema)
    findings = []
    for error in sorted(validator.iter_errors(content), key=lambda e: list(e.absolute_path)):
        location = ".".join(str(part) for part in error.absolute_path) or "(root)"
        findings.append(f"schema: {location}: {error.message[:120]}")
    return findings


def generic_findings(content: Any) -> list[str]:
    findings = []
    for path, text in walk_strings(content):
        for rule, pattern in GENERIC_PATTERNS.items():
            for match in pattern.finditer(text):
                token = match.group(0)
                if rule == "ticket id" and TICKET_EXCEPTIONS.match(token):
                    continue
                if rule == "phone number" and (
                    YEAR_RANGE.match(token.strip()) or sum(c.isdigit() for c in token) < 9
                ):
                    continue
                findings.append(f"leak pattern '{rule}' at {path}")
        for match in URL_PATTERN.finditer(text):
            host = re.sub(r"^(?:https?://)?", "", match.group(0), flags=re.IGNORECASE)
            host = host.split("/")[0].lower()
            if host not in ALLOWED_URL_HOSTS:
                findings.append(f"url outside the allowlist at {path}")
    return findings


def load_allowed_numbers(path: Path) -> set[str]:
    allowed = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        entry = line.split("#", 1)[0].strip()
        if entry:
            allowed.add(entry)
    return allowed


def number_findings(content: Any, allowed: set[str]) -> list[str]:
    findings = []
    for path, text in walk_strings(content):
        for match in NUMBER_PATTERN.finditer(text):
            token = match.group(0)
            if token in allowed or YEAR.match(token):
                continue
            findings.append(f"number not on the CV allowlist at {path}")
    return findings


def load_denylist(path: Path) -> list[re.Pattern[str]]:
    patterns = []
    for line in path.read_text(encoding="utf-8").splitlines():
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        if entry.startswith("re:"):
            patterns.append(re.compile(entry[3:]))
        else:
            patterns.append(re.compile(r"(?<!\w)" + re.escape(entry) + r"(?!\w)", re.IGNORECASE))
    return patterns


def denylist_findings(content: Any, patterns: list[re.Pattern[str]]) -> list[str]:
    findings = []
    for path, text in walk_strings(content):
        for index, pattern in enumerate(patterns, start=1):
            if pattern.search(text):
                findings.append(f"private denylist entry #{index} matched at {path}")
    return findings


def _approved(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [item for item in items if item.get("approved") is True]


def build_public(content: dict[str, Any]) -> dict[str, Any]:
    """The published subset: approved lines only, no flags."""
    profile = {
        key: value["text"]
        for key, value in content["profile"].items()
        if value.get("approved") is True
    }
    experience = []
    for entry in _approved(content["experience"]):
        experience.append(
            {
                "employer": entry["employer"],
                "role": entry["role"],
                "start": entry["start"],
                "end": entry["end"],
                "bullets": [b["text"] for b in _approved(entry["bullets"])],
            }
        )
    case_studies = []
    for study in _approved(content["case_studies"]):
        if study["employer_approval"] != "granted":
            continue
        case_studies.append(
            {
                "id": study["id"],
                "title": study["title"],
                "summary": study["summary"]["text"] if study["summary"]["approved"] else "",
                "sections": [
                    {
                        "heading": section["heading"],
                        "paragraphs": [p["text"] for p in _approved(section["paragraphs"])],
                    }
                    for section in _approved(study["sections"])
                ],
            }
        )
    return {
        "version": content["version"],
        "profile": profile,
        "links": [{"label": x["label"], "url": x["url"]} for x in _approved(content["links"])],
        "skills": [
            {"category": x["category"], "items": x["items"]} for x in _approved(content["skills"])
        ],
        "experience": experience,
        "case_studies": case_studies,
        "languages": [x["name"] for x in _approved(content["languages"])],
    }


def default_denylist() -> Path:
    override = os.environ.get("CONTENT_DENYLIST")
    return Path(override) if override else Path.home() / ".portfolio" / "denylist.txt"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--content", type=Path, default=Path("content/content.yaml"))
    parser.add_argument("--schema", type=Path, default=Path("content/schema/content.schema.json"))
    parser.add_argument("--allowed-numbers", type=Path, default=Path("content/allowed-numbers.txt"))
    parser.add_argument("--denylist", type=Path, default=None)
    parser.add_argument(
        "--allow-missing-denylist",
        action="store_true",
        help="CI only: the private denylist is not available there",
    )
    parser.add_argument("--build", type=Path, default=None, help="write the published JSON here")
    args = parser.parse_args(argv)

    content = yaml.safe_load(args.content.read_text(encoding="utf-8"))
    schema = json.loads(args.schema.read_text(encoding="utf-8"))

    findings = schema_findings(content, schema)
    if findings:  # the other checks assume a valid structure
        print("\n".join(findings), file=sys.stderr)
        return 1

    findings += generic_findings(content)
    findings += number_findings(content, load_allowed_numbers(args.allowed_numbers))

    denylist_path = args.denylist or default_denylist()
    if denylist_path.exists():
        findings += denylist_findings(content, load_denylist(denylist_path))
    elif args.allow_missing_denylist:
        print("note: private denylist not available, skipped (CI)", file=sys.stderr)
    else:
        findings.append("the private denylist file is missing: refusing to pass without it")

    if findings:
        print("\n".join(sorted(set(findings))), file=sys.stderr)
        return 1

    if args.build:
        args.build.parent.mkdir(parents=True, exist_ok=True)
        args.build.write_text(
            json.dumps(build_public(content), indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    print("content checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

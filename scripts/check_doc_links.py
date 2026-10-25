"""Checks that the relative links in the documentation point at something that exists.

    python3 scripts/check_doc_links.py [root]

It reads README.md, SECURITY.md and every Markdown file under docs/, finds `[text](target)` links
and `[text]: target` definitions, and fails when
  - a relative link points at a file or folder that does not exist, or
  - a link to a Markdown file has a `#fragment` that no heading of that file produces
    (GitHub's anchor rules: lower case, punctuation dropped, spaces to hyphens, repeats numbered).
Links to other sites (http, https, mailto) are not followed, and neither is anything inside a code
block or inline code. Standard library only.
"""

import re
import sys
from pathlib import Path

LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
IMAGE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
DEFINITION = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(\S+)", re.MULTILINE)
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
EXTERNAL = ("http://", "https://", "mailto:", "tel:")


def strip_code(text: str, inline: bool = True) -> str:
    """The text without fenced code blocks (and inline code), with the line count unchanged."""
    out: list[str] = []
    fence = ""
    for line in text.splitlines():
        marker = line.lstrip()[:3]
        if fence:
            if marker == fence:
                fence = ""
            out.append("")
            continue
        if marker in ("```", "~~~"):
            fence = marker
            out.append("")
            continue
        out.append(re.sub(r"`[^`]*`", "", line) if inline else line)
    return "\n".join(out)


def slug(heading: str) -> str:
    """GitHub's anchor for a heading (without the number added to repeats)."""
    text = re.sub(r"`", "", heading)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # a link in a heading keeps its text
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    return re.sub(r"\s", "-", text)


def anchors(path: Path) -> set[str]:
    found: set[str] = set()
    seen: dict[str, int] = {}
    for line in strip_code(path.read_text(encoding="utf-8"), inline=False).splitlines():
        match = HEADING.match(line)
        if not match:
            continue
        base = slug(match.group(2))
        count = seen.get(base, 0)
        seen[base] = count + 1
        found.add(base if count == 0 else f"{base}-{count}")
    return found


def documents(root: Path) -> list[Path]:
    files = [root / "README.md", root / "SECURITY.md"]
    files += sorted((root / "docs").rglob("*.md"))
    return [f for f in files if f.is_file()]


def problems_in(path: Path, root: Path) -> list[str]:
    text = strip_code(path.read_text(encoding="utf-8"))
    targets = LINK.findall(text) + IMAGE.findall(text) + DEFINITION.findall(text)
    found: list[str] = []
    for target in targets:
        if target.startswith(EXTERNAL):
            continue
        target = target.strip("<>")
        name, _, fragment = target.partition("#")
        where = path.relative_to(root).as_posix()
        if not name:
            resolved = path  # a link to a heading of the same file
        else:
            resolved = (path.parent / name.split("?")[0]).resolve()
            if not resolved.exists():
                found.append(f"{where}: '{target}' does not exist")
                continue
        if fragment and resolved.is_file() and resolved.suffix == ".md":
            if fragment.lower() not in anchors(resolved):
                found.append(f"{where}: '{target}' has no heading '{fragment}'")
    return found


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else ".").resolve()
    files = documents(root)
    if not files:
        print(f"no documentation found under {root}", file=sys.stderr)
        return 2
    problems = [p for f in files for p in problems_in(f, root)]
    for problem in problems:
        print(f"BROKEN LINK {problem}", file=sys.stderr)
    if problems:
        print(f"{len(problems)} broken link(s) in {len(files)} files", file=sys.stderr)
        return 1
    print(f"links ok in {len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

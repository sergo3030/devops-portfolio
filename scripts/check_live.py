"""Checks that the deployed site and the API it calls work together, from the outside.

    python3 scripts/check_live.py <site-url> [attempts] [seconds-between]

It needs no address of the API: it reads the site's Content-Security-Policy and takes the one
origin the page may connect to, so a site that points at an old or missing function fails here.
Then it asks the API what a browser on the site would ask, and what a browser on another website
must not get: health and version, the content, the CORS headers for the site and for a stranger,
the security headers, and that a write is refused. The calls run one at a time because the function
allows two concurrent executions. A failing attempt is repeated (3 times, 20 s apart by default) so
a cold start or a brief CDN delay does not raise an alarm. Standard library only: it runs on the
plain runner and needs no credentials.
"""

import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any

COMMIT = re.compile(r"^[0-9a-f]{40}$")
VERSION = re.compile(r"^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$")
POLICY = re.compile(r'http-equiv="Content-Security-Policy"\s+content="([^"]*)"')
STRANGER = "https://evil.example"
CONTENT_KEYS = ("profile", "links", "skills", "experience", "case_studies", "languages")
APPROVAL_KEYS = {"approved", "employer_approval"}
TIMEOUT = 30.0


@dataclass
class Answer:
    status: int
    headers: dict[str, str]
    body: bytes


@dataclass
class Report:
    problems: list[str] = field(default_factory=list)
    facts: list[str] = field(default_factory=list)

    def expect(self, ok: bool, name: str, detail: str) -> bool:
        """Records a check. A passed check prints its detail, a failed one says what is wrong."""
        if ok:
            self.facts.append(f"{name}: {detail}")
        else:
            self.problems.append(f"{name}: {detail}")
        return ok


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args: Any, **kwargs: Any) -> None:
        return None


def call(url: str, method: str = "GET", headers: dict[str, str] | None = None) -> Answer | str:
    """The answer, or a sentence saying why there is none. Any status counts as an answer."""
    request = urllib.request.Request(  # noqa: S310 - the scheme is checked in main()
        url, method=method, headers={"Accept": "application/json", **(headers or {})}
    )
    opener = urllib.request.build_opener(_NoRedirect) if method != "GET" else None
    try:
        open_url = opener.open if opener else urllib.request.urlopen  # noqa: S310
        with open_url(request, timeout=TIMEOUT) as response:
            return Answer(
                response.status,
                {k.lower(): v for k, v in response.headers.items()},
                response.read(),
            )
    except urllib.error.HTTPError as error:
        return Answer(error.code, {k.lower(): v for k, v in error.headers.items()}, error.read())
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        return f"no answer from {url}: {error}"


def origin_of(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}"


def is_allowed_address(url: str) -> bool:
    return url.startswith(("https://", "http://127.0.0.1", "http://localhost"))


def api_origin(page: str, report: Report) -> str | None:
    """The one origin besides the site itself that the page's policy lets it connect to."""
    match = POLICY.search(page)
    if not match:
        report.expect(False, "site policy", "the page has no Content-Security-Policy")
        return None
    connect = re.search(r"(?:^|;\s*)connect-src ([^;]*)", html.unescape(match.group(1)))
    others = [t for t in (connect.group(1).split() if connect else []) if t != "'self'"]
    if len(others) != 1:
        report.expect(
            False,
            "site policy",
            f"connect-src should name exactly one API origin, it names {others}",
        )
        return None
    origin = others[0]
    if origin_of(origin) != origin or not is_allowed_address(origin):
        report.expect(False, "site policy", f"{origin} is not a plain https origin")
        return None
    report.expect(True, "site policy", f"the page may call {origin}")
    return origin


def json_body(answer: Answer) -> Any:
    try:
        return json.loads(answer.body)
    except ValueError:
        return None


def keys_anywhere(value: Any) -> set[str]:
    if isinstance(value, dict):
        return set(value) | {k for v in value.values() for k in keys_anywhere(v)}
    if isinstance(value, list):
        return {k for v in value for k in keys_anywhere(v)}
    return set()


def check_security_headers(answer: Answer, name: str, report: Report) -> None:
    h = answer.headers
    wrong = [
        label
        for label, ok in [
            ("nosniff", h.get("x-content-type-options") == "nosniff"),
            (
                "Content-Security-Policy",
                "default-src 'none'" in h.get("content-security-policy", ""),
            ),
            ("Referrer-Policy", h.get("referrer-policy") == "no-referrer"),
            ("X-Frame-Options", h.get("x-frame-options") == "DENY"),
            ("Strict-Transport-Security", "max-age=" in h.get("strict-transport-security", "")),
            ("no uvicorn banner", "uvicorn" not in h.get("server", "").lower()),
        ]
        if not ok
    ]
    report.expect(
        not wrong,
        f"{name} headers",
        f"missing or wrong: {wrong}" if wrong else "security headers present",
    )


def check_api(origin: str, site: str, report: Report) -> None:
    """What a browser on `site` gets, and what one on another website must not get."""
    health = call(f"{origin}/health", headers={"Origin": site})
    if isinstance(health, str):
        report.expect(False, "/health", health)
    else:
        body = json_body(health)
        ok = (
            health.status == 200
            and isinstance(body, dict)
            and body.get("status") == "ok"
            and VERSION.match(str(body.get("version", ""))) is not None
            and COMMIT.match(str(body.get("git_sha", ""))) is not None
        )
        shown = f"{health.status} {body!r}"
        if ok and isinstance(body, dict):
            shown = f"ok, version {body['version']}, commit {str(body['git_sha'])[:7]}"
        report.expect(ok, "/health", shown)
        report.expect(
            health.headers.get("cache-control") == "no-store",
            "/health cache",
            f"cache-control is {health.headers.get('cache-control')!r}",
        )
        report.expect(
            health.headers.get("access-control-allow-origin") == site
            and "access-control-allow-credentials" not in health.headers,
            "/health CORS",
            f"allow-origin is {health.headers.get('access-control-allow-origin')!r}"
            f", the site is {site!r}",
        )
        check_security_headers(health, "/health", report)

    content = call(f"{origin}/content", headers={"Origin": site})
    if isinstance(content, str):
        report.expect(False, "/content", content)
    else:
        body = json_body(content)
        has_shape = isinstance(body, dict) and all(k in body for k in CONTENT_KEYS)
        report.expect(
            content.status == 200 and has_shape,
            "/content",
            f"answered {content.status} {'with' if has_shape else 'without'} the expected keys",
        )
        leaked = sorted(keys_anywhere(body) & APPROVAL_KEYS)
        report.expect(
            content.status == 200 and not leaked,
            "/content approval state",
            f"leaked {leaked}"
            if leaked
            else ("none in the answer" if content.status == 200 else "no content to look at"),
        )
        report.expect(
            content.headers.get("cache-control", "").startswith("public, max-age=300"),
            "/content cache",
            f"cache-control is {content.headers.get('cache-control')!r}",
        )
        report.expect(
            content.headers.get("access-control-allow-origin") == site,
            "/content CORS",
            f"allow-origin is {content.headers.get('access-control-allow-origin')!r}"
            f", the site is {site!r}",
        )

    stranger = call(f"{origin}/health", headers={"Origin": STRANGER})
    if isinstance(stranger, str):
        report.expect(False, "CORS for another website", stranger)
    else:
        leak = stranger.headers.get("access-control-allow-origin")
        report.expect(
            stranger.status == 200 and leak is None,
            "CORS for another website",
            f"allowed {leak!r}"
            if leak
            else (
                "no CORS headers, as intended"
                if stranger.status == 200
                else f"the API answered {stranger.status}, so nothing can be said"
            ),
        )

    write = call(f"{origin}/content", method="POST", headers={"Origin": site})
    if isinstance(write, str):
        report.expect(False, "write refused", write)
    else:
        report.expect(
            write.status == 405 and write.headers.get("allow") == "GET, OPTIONS",
            "write refused",
            f"POST answered {write.status}, Allow is {write.headers.get('allow')!r}",
        )


def check_once(site_url: str) -> Report:
    report = Report()
    page = call(site_url)
    if isinstance(page, str):
        report.expect(False, "site", page)
        return report
    report.expect(page.status == 200, "site", f"{site_url} answered {page.status}")
    origin = api_origin(page.body.decode("utf-8", "replace"), report)
    if origin is not None:
        check_api(origin, origin_of(site_url), report)
    return report


def write_summary(report: Report, attempt: int) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    lines = [
        "### Live check",
        f"- result: {'FAILED' if report.problems else 'passed'} (attempt {attempt})",
    ]
    lines += [f"- ok: {fact}" for fact in report.facts]
    lines += [f"- **FAIL: {problem}**" for problem in report.problems]
    with open(path, "a", encoding="utf-8") as summary:
        summary.write("\n".join(lines) + "\n")


def main(argv: list[str]) -> int:
    if not 1 <= len(argv) <= 3:
        print("usage: check_live.py <site-url> [attempts] [seconds]", file=sys.stderr)
        return 2
    site_url = argv[0]
    attempts = int(argv[1]) if len(argv) > 1 else 3
    pause = float(argv[2]) if len(argv) > 2 else 20.0
    if not is_allowed_address(site_url):
        print("the site URL must be https (or a local test server)", file=sys.stderr)
        return 2

    report = Report()
    for attempt in range(1, attempts + 1):
        report = check_once(site_url)
        for fact in report.facts:
            print(f"ok   {fact}")
        for problem in report.problems:
            print(f"FAIL {problem}", file=sys.stderr)
        if not report.problems:
            write_summary(report, attempt)
            print("live check passed: the site and the API work together")
            return 0
        print(f"attempt {attempt}/{attempts}: {len(report.problems)} problem(s)", file=sys.stderr)
        if attempt < attempts:
            time.sleep(pause)
    write_summary(report, attempts)
    print(f"live check FAILED ({len(report.problems)} problem(s))", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

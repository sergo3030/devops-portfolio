# Stability: flakiness, speed and pinned tools

Task 20. The goal is a CI that fails only when something is wrong, with every tool version known
and updated on purpose. Numbers below were read from the run history on 2026-10-25.

## What failed, and why

Of the last 80 runs of the `ci` workflow, 20 failed. **16 of the 20 were the same flake**: a
`429 Too Many Requests` from `public.ecr.aws` on the anonymous pull of the Lambda Web Adapter image
(the shared runners share one anonymous limit). Four were real failures (code or configuration).

| Cause | Fix | Decision |
|---|---|---|
| Anonymous pull of the adapter image in pull request runs | The jobs log in to public ECR with the read-only plan role | D40 |
| The same on pushes to `main` | The plan role also trusts `main`, and `ci.yml` assumes it there | D49 |
| The same in pull requests that Dependabot opens (they cannot read Actions secrets) | A Dependabot secret with the account ID, managed in `infra/github` | D51 |

The login steps fall back to an anonymous pull if they fail, so a missing login is a slower build,
not a broken one, and the pull is retried three times.

Other sources of flakiness that are handled on purpose:

| Source | Handling |
|---|---|
| The Pages CDN needs a minute to catch up after a deploy | `scripts/verify-site.sh` retries (nine attempts, ten seconds apart) |
| A cold Lambda takes 4 to 5 seconds | The site waits eight seconds; `synthetic` and the deploy check retry |
| The Trivy vulnerability database download | Retried, from two mirrors |
| A rejected or unapproved deploy leaves a run "waiting" | Documented in `runbook-prod.md`; the next build queues behind it |

A red run on `main` is investigated, not re-run blindly. A re-run is fine for a known flake
that has a recorded cause.

## How fast it is, and why there is no cache

Median and slowest job time over twelve recent green runs:

| Job | Median | Slowest |
|---|---|---|
| `opentofu (fmt, validate, test)` | 56 s | 61 s |
| `e2e (stack, site)` | 50 s | 66 s |
| `image (hadolint, build, smoke)` | 41 s | 49 s |
| `web (lint, test, build)` | 28 s | 34 s |
| `iac (checkov)` | 22 s | 26 s |
| `python (ruff, pytest)` | 21 s | 26 s |
| `workflows (actionlint, zizmor)` | 13 s | 16 s |
| `secrets (gitleaks)` | 5 s | 8 s |

The jobs run in parallel, so a whole run takes about a minute. A cache would save a few seconds
per job and adds a way to poison a build from a pull request (zizmor audits for it), so **no
caching is used** (D52). Revisit it if any job passes two minutes.

## The streak

`just ci-streak` (`scripts/ci_streak.py`) counts the consecutive green runs of `ci` on `main`,
newest first. A run that was cancelled because a newer push replaced it, or one still running, is
skipped; a failure ends the streak. Task 20's goal is ten in a row. It was six on 2026-10-25, and
it grows with each merge.

## Pinned tools

Everything is pinned exactly. What differs is who notices a new version.

| Tool | Pinned in | Updated by |
|---|---|---|
| actionlint, zizmor, check-jsonschema, shellcheck, checkov | `tools/pyproject.toml` and `tools/uv.lock` (hashes) | Dependabot, weekly, one grouped pull request |
| Python dependencies of the API, Node dependencies of the site | `app/uv.lock`, `web/package-lock.json` | Dependabot |
| Actions, base images, OpenTofu providers | SHA pins, image digests, `.terraform.lock.hcl` | Dependabot |
| uv | `version:` of `astral-sh/setup-uv` in the workflows | You, with the weekly report |
| OpenTofu | `tofu_version:` of `opentofu/setup-opentofu` in the workflows | You, with the weekly report |
| gitleaks, hadolint | `GITLEAKS_VERSION`, `HADOLINT_VERSION` and their checksums in `ci.yml` | You, with the weekly report |
| Trivy | `version` and `sha256` in `scripts/install-trivy.sh` | You, with the weekly report |

The tools in the last four rows are not visible to Dependabot, so two things watch them:

- **`scripts/check-tool-pins.sh`** (in CI) fails if one tool is pinned to two versions, which is
  what a half-finished bump looks like, or if a pin can no longer be found.
- **The weekly `tool-versions` workflow** (`scripts/tool-versions.sh`, Mondays) compares each pin
  with the tool's latest release and fails, so GitHub emails you, when a pinned version is behind a
  release that is **at least 14 days old**. A younger release is listed as "waiting", the same
  cooldown Dependabot uses. `just tool-versions` runs it locally. GitHub pauses scheduled
  workflows after 60 days without repository activity; run it by hand after a quiet spell.

**To bump one of them:** change every place in the table (the check tells you if you missed one).
For gitleaks, hadolint and Trivy, download the release archive, compare its SHA-256 with the
release's published checksums file, and update the version and the checksum together. Then run
`just test-scripts` and open a pull request. The Docker image of uv (`app/Dockerfile`) is a
different pin, tracked by Dependabot's docker ecosystem, and does not have to match the CI version.

To run a Python tool: `uv run --project tools --locked <tool> ...`. Checkov runs as a module
(`python -m checkov.main`) because its console script is a plain `.py` file that Windows cannot
launch.

# Decisions and deviations from the baseline plan

The baseline plan ([aws-lambda-baseline-plan.md](aws-lambda-baseline-plan.md)) is the
source of truth. Where practice differs, the difference is recorded here with the
reason, so nothing changes silently.

## Decided

| # | Decision | Reason |
|---|---|---|
| D1 | Region `us-east-1`, no custom domain | Cheapest, fewest surprises. A domain is a yearly cost and optional |
| D2 | `just` as task runner, recipes run in Git Bash | Readable showcase. The path to Git Bash is explicit, because a bare `bash` can be the WSL stub |
| D3 | Rebase-and-merge, one task per branch and pull request | Keeps the commit history as written. Each commit must pass CI on its own |
| D4 | Repo starts private and goes public at a gate | GitHub Free offers CodeQL, dependency review, secret scanning and push protection on public repositories only |
| D5 | Task 4 is split: 4a (gitleaks and checkov in CI) now, 4b (CodeQL, dependency review) at the go-public step | Follows from D4 |
| D6 | Dependabot uses the `opentofu` ecosystem, not `terraform` | GitHub added a dedicated ecosystem on 2025-12-16. `opentofu`, `docker` and `npm` entries are added in tasks 6, 11 and 12 |
| D7 | Budget and Cost Anomaly Detection are created in task 6 through OpenTofu, not by hand in task 5 | "Create nothing by hand", and they must be tagged and destroyable |
| D8 | Gitleaks runs in CI from a release pinned by SHA-256 | No third-party action needed |
| D9 | The `apply` role is created in task 8, not task 6 | It trusts the protected environment's OIDC claim, which can only be verified in task 8. It is also the most powerful role |
| D10 | The `plan` role uses a custom read-only policy for the services in use, not `ReadOnlyAccess` | Least privilege. Missing read actions show up in the first CI plan (task 8) and are added then |
| D11 | A permission boundary caps every project role: allowed services only, one region, expensive services denied | The cost-risk allowlist in IAM form. Checkov findings on the boundary are skipped with a stated reason |
| D12 | Trust policies use the immutable subject format `repo:OWNER@OWNER_ID/REPO@REPO_ID:...` | Repositories created after 2026-07-15 use it. All three contexts were verified from real tokens on 2026-10-21 (see below) |

| D13 | Local bootstrap identity is the IAM user `portfolio-admin` (MFA, no keys) with `aws login` | Temporary credentials, no stored keys. Root stays unused. Needed again for teardown and the rebuild rehearsal |
| D14 | Reserved concurrency cannot be set: the account's Lambda concurrent executions quota is 10 | AWS requires about 100 unreserved. The quota is adjustable. The limit of 10 acts as a natural cap while it stays low. See open items |

| D15 | The repository went public on 2026-10-21, in two applies (visibility, then secret scanning and push protection) | GitHub rejects the security settings in the same update as the flip. The `enable_secret_scanning` variable controls the second step |

| D16 | Branch protection is a ruleset with no bypass actors. Break-glass is `ruleset_enforcement=disabled` applied from the laptop | The rules bind the owner too. The escape hatch is code, so it is reviewable and rehearsed |
| D17 | Only GitHub-owned actions plus an allowlist may run, and every action must be SHA-pinned (enforced by GitHub, not only by zizmor) | Supply-chain control. A new action is a reviewed change to `allowed_action_patterns` |
| D18 | Fork PR approval and private vulnerability reporting are set with `gh api` and checked by `just github-settings-check` | No provider resource exists for them |

| D19 | The AWS account ID reaches workflows as the GitHub Actions **secret** `AWS_ACCOUNT_ID`, set by OpenTofu from `TF_VAR_aws_account_id` | The role ARN needs it, and it must not appear in files or public logs. It is not a credential, but only secrets are masked by GitHub. A first version used an Actions variable on the assumption that the credentials action masks the ID. It does not: the first CI plan printed the ID in the step header and in every ARN line. That run's log was deleted, and neither the action nor an `add-mask` step can hide a variable from the step that first uses it |
| D20 | CI plans the bootstrap root with a placeholder alert email, and the Budget and anomaly subscription use `ignore_changes` | The email is personal and is not stored in GitHub. To change the email or thresholds, replace the two resources (see the bootstrap runbook). Drift on those attributes is not detected |
| D21 | The `apply` role is created in task 8 with no resource permissions, only the prod state keys | The role that deploys from the protected environment never holds more than the code in the repository needs. Task 14 adds its permissions with the code that needs them |

| D22 | The `plan` workflow runs only when `infra/bootstrap/**` changes, so it is not a required check. Its job summary shows only the plan's one-line result | A path-filtered check that does not run would block unrelated pull requests. A plan in a public summary could expose the account ID |

| D23 | The API's test client keeps the stable `httpx 0.28.1`, and pytest ignores only Starlette's one deprecation notice about it | Starlette now prefers `httpx2`, a new package from the Pydantic organisation whose newest releases are days old. Revisit when Starlette removes httpx support. All other warnings are errors |
| D24 | The API is a plain module-level `app` with the lifespan loading and validating the content, routers in their own module, a singleton content store and `uvicorn.run` under `__main__`. A missing or invalid content file aborts the start-up. Docs routes are off unless `ENABLE_DOCS=1` | This is the layout the project owner prefers for FastAPI services. A broken content build must not serve, and the lifespan is the idiomatic place for start-up work (task 21 reuses it for the database client). Typing is kept: a content store and a `get_content` dependency instead of an untyped `app.state`, so tests override the dependency or point `CONTENT_FILE` at a file. A first version used a factory function with everything nested in it: it failed fast just as well, but was harder to read and needed `--factory` |

| D25 | The running version has one source, the environment variable `APP_VERSION` (and `GIT_SHA`), set by the release build from the git tag. `pyproject.toml` keeps a placeholder, and `/health` and OpenAPI report the variable | The first version hardcoded `0.1.0` in two places that could drift, and the plan had no release mechanism at all. A test fails if a release version is hardcoded in the package |
| D26 | Releases are tag-driven (task 15a, added to the plan): a `vX.Y.Z` tag builds the image and creates a GitHub Release with generated notes. `release-please` is not used | `release-please` opens a pull request with `GITHUB_TOKEN`, which does not trigger CI, so the required checks could never pass. Making them run needs a personal token or a GitHub App key stored in GitHub, which we avoid |

| D27 | The container build, lint and smoke test are one required CI job, `image (hadolint, build, smoke)`, with no path filter. It uses plain `docker build` and `docker compose` with provenance attestations off, so no third-party Docker action is allowed or needed | A path-filtered required check would block unrelated pull requests. Lambda does not accept multi-architecture images, and provenance attestations turn the image into an OCI index. The adapter, the base image and the `uv` image are pinned by digest |
| D28 | Docker stays CI-only. WSL 2 with Docker Engine was offered (the laptop can run it) and declined by the owner. Revisit if the CI feedback loop for container work becomes too slow | Keeps the local toolchain native and small. CI is the source of truth for container behaviour either way |
| D29 | The contract between the API and the site is the JSON Schema generated from the Pydantic models (`content/schema/published.schema.json`, committed, a test fails when it is stale). The site generates its TypeScript types from that file and a test validates the embedded snapshot against it | One source of truth for the shape of the data. An API change that breaks the site fails a build instead of the live page. Hand-written types would drift |
| D30 | The site is built to be redesigned later: colours, spacing and type come from CSS variables (`tokens.css`), components are pure functions of their props and render on a server without browser globals (tested), the title, description and Content-Security-Policy in `index.html` are filled from the content at build time, and bundle size has a budget (90 KB JS, 15 KB CSS, gzipped) | The owner plans a UI/UX pass after the backend and deployment are done (Could item in the plan). These choices keep that pass from touching data loading, tests or the build. Pre-rendering and a theme switch become small changes |
| D31 | The web toolchain is pinned to exact versions with `ignore-scripts`, and ESLint stays on 9 and TypeScript on 6.0.3 for now. Dependabot ignores the next major of `typescript`, `eslint` and `@eslint/js` | The lint plugins (React hooks, accessibility, typescript-eslint) lag the newest ESLint and TypeScript majors. A broken lint setup blocks every pull request, so those jumps are deliberate tasks. Install scripts of dependencies never run on the laptop or in CI |
| D32 | Live data (task 12c): the site renders the saved copy first and swaps in the API's content if it answers within 5 s. With no API configured (`VITE_API_URL` unset in a production build) it fetches nothing and shows no status. Data from the API is checked by a complete structural guard, only `http(s)` links pass, and an error boundary falls back to the saved copy. Both requests use `cache: 'no-cache'`. The status line is at the bottom of the page | Saying "API offline" about an API that was never configured would be false. The API is not trusted: a bad response must not break the page or add a `javascript:` link. In the browser check, `/content` (cacheable for 5 minutes) was answered from the HTTP cache while the API was down and the page claimed "Live from API", so the status is made honest by revalidating. A late result at the bottom cannot move the content. Known trade-off: a cold Lambda start slower than 5 s shows "offline" while the API is fine |
| D33 | The site is published by its own workflow, `pages.yml`, on push to `main` (path-filtered to the site's inputs) and on demand. Build and deploy are separate jobs: the build has a read-only token, only the deploy job has `pages: write` and `id-token: write`. The deploy is verified by comparing the live `index.html` with the SHA-256 of the built one and loading its assets. It is not a required check and the Pages environment stays limited to `main` | Merging is the approval to publish, so a deploy needs no second gate. Keeping the write permissions in one small job limits what a compromised build step can do. A hash comparison proves the CDN serves this build, not an older cached one. The verify script was tested against a local server (match, wrong hash, wrong path). The deploy job itself cannot run before the first merge, because the environment refuses branches |

## Verified OIDC subject formats (2026-10-21)

Read from the claims of real GitHub OIDC tokens (audience `sts.amazonaws.com`, issuer
`https://token.actions.githubusercontent.com`), with a temporary diagnostic workflow
that printed only the non-secret claims and was removed afterwards.

| Where the job runs | `sub` claim | Trusted by |
|---|---|---|
| Pull request (same repository) | `repo:sergo3030@61195883/devops-portfolio@1425913518:pull_request` | `portfolio-plan` |
| Push to `main` | `repo:sergo3030@61195883/devops-portfolio@1425913518:ref:refs/heads/main` | `portfolio-ecr-push` |
| Job with `environment: prod` | `repo:sergo3030@61195883/devops-portfolio@1425913518:environment:prod` | `portfolio-apply` (task 8b) |

Notes:
- For the `prod` job the `environment` claim is `prod`, and the job only started after the
  owner approved the deployment (recorded in the run's approvals).
- The docs do not say whether fork pull requests receive OIDC tokens. Secrets are not passed
  to fork workflows and `GITHUB_TOKEN` is read-only there. Not tested with a real fork, so
  the plan workflow also skips fork pull requests explicitly.

## Open items (decided when the task that needs them starts)

| Item | Task | Issue |
|---|---|---|
| Read-only `plan` role versus S3 native locking | 6, 8 | `tofu plan` writes a lock object. Allow `PutObject` and `DeleteObject` on the lock key only, or plan with `-lock=false` |
| The `github` root needs a GitHub token | 7, 8, 22 | `GITHUB_TOKEN` cannot administer repository settings. Plan and apply that root locally, and let CI plan only `prod` |
| Credentials for the one-time bootstrap | 6 | Prefer short-lived credentials (`aws login`) over stored access keys. Verify against the current AWS CLI docs first |
| Reserved concurrency needs the account limit minus 100 | 14, 18 | The quota is 10 (checked). Either request an increase to 1,000 (free, adjustable) or drop reserved concurrency and keep the low account limit as the cap. Task 14 makes `reserved_concurrency` an optional variable |
| `verify-clean` must not rely on the tag search alone | 18a | The tagging API does not list IAM roles. Also list roles by name prefix |
| Image format on Lambda | 15 | Build with provenance attestations off, so Lambda accepts the manifest |
| Budget alert email address | 6, 18 | Pass through a gitignored tfvars or `TF_VAR_*`, never in the repository |
| Branch protection, required-reviewer environments, Pages on a private repository | 7, 8, 13 | Not listed for the Free plan. Confirm through the API, or wait for the go-public step |
| Tools pinned inline in workflows (`zizmor`, `actionlint-py`, `check-jsonschema`, `checkov`, uv) | 20 | Dependabot does not update them. Move them into a tracked manifest or accept manual bumps |

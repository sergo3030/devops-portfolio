# Portfolio Platform on AWS Lambda: Baseline Plan

Status: planning baseline, October 2026. No implementation exists yet.
Purpose: a public portfolio whose real goal is to demonstrate DevOps skills (OpenTofu/Terraform, AWS integration, secure CI, secrets handling) and to show that you can learn new tools. FastAPI, Python, Docker and GitHub Actions are existing strengths. OpenTofu, AWS and React are the new tools. It is deliberately more than a portfolio needs, and the site says so.

## 1. Goals and constraints

**Priorities, in order**
1. OpenTofu/Terraform with real AWS integration: modules, remote state, keyless CI login (OIDC), drift detection, policy checks.
2. Repository maintenance: code scans, Dependabot, branch protection managed as code.
3. Solid, stable CI.
4. Fully secured secrets.
5. A small Python (FastAPI) and React app running as a Docker container on AWS Lambda. The Python, FastAPI and Docker parts use skills you already have, so keep them simple and spend the effort on the infrastructure.

**Hard constraints**
- No recurring payments beyond cents. A one-time payment under $50 is acceptable. A domain is a yearly cost and is optional.
- Production runs a Docker container.
- Nothing hosted on a home network.
- No secrets in the repository, and nothing sensitive stored in GitHub.
- Content is public-safe: no employer-confidential details, ticket IDs, internal names, phone, email or photo.
- Reproducible from a clean clone with a few documented commands.
- Local machine is Windows without WSL, so Docker does not run locally. Everything else runs natively, and GitHub Actions is the source of truth for container behavior.

**Account facts**
- AWS offers no hard spending cap, so the cost guards in section 6 are built in from the start.
- Always-free services (Lambda, DynamoDB, CloudWatch Logs allowance) still apply. Verify the current limits before relying on them.

## 2. Architecture

```
Visitor
  |
  |-- static React site on GitHub Pages (CV, timeline, skills, About this project)
  |        saved content snapshot is built in, so the site works if the API is offline
  |
  '-- fetch https://<id>.lambda-url.<region>.on.aws   (CORS locked to the site origin)
           |
           v
     AWS Lambda (container image from ECR, FastAPI via the Lambda Web Adapter)
           |
           '-- DynamoDB table (optional: contact messages with a 90-day TTL)
```

- **Frontend:** Vite, React, TypeScript. Renders content from `/content`, a simple timeline and a skills filter. No 3D and no charting libraries.
- **API:** FastAPI with Pydantic. Endpoints: `/health`, `/content` (content baked into the image). Optional: `/contact`.
- **Container:** multi-stage Dockerfile, slim base, non-root user, health check. The same image runs locally and on Lambda.
- **Function URL:** a built-in public HTTPS address for the function. No API Gateway.
- **Optional edge:** Cloudflare in front with a domain, adding a secret header that the API checks so the Function URL cannot be called directly.

## 3. OpenTofu layout

| Root | What it manages | State |
|---|---|---|
| `infra/bootstrap` | S3 state bucket (versioned, encrypted, private, native locking), GitHub OIDC provider, IAM roles, permission boundary, Budget | Local first, then migrated into the bucket |
| `infra/github` | Repository settings: branch protection, required checks, security features, Pages, environments | Remote (S3) |
| `infra/prod` | ECR repo (keeps 2 images), Lambda, Function URL, least-privilege role, reserved concurrency, log retention, optional DynamoDB | Remote (S3) |

**IAM roles (all assumed through GitHub OIDC, no stored keys)**
- `plan`: read-only, assumable from pull requests in this repository only.
- `ecr-push`: can push images to the one ECR repository only, from the main branch.
- `apply`: assumable only from a protected GitHub environment that needs your approval.

**Rules**
- Use OpenTofu. Keep the code valid for Terraform where easy.
- Do not manage secret values in OpenTofu, so the state contains no secrets.
- Pin provider versions and commit the lock file.
- A few meaningful modules with typed inputs and outputs, with generated docs.

## 4. CI/CD and repository maintenance

**Workflows**
1. `ci`: lint, tests, type check, Gitleaks, `actionlint`, `zizmor`, OpenTofu `fmt` and `validate`, Hadolint, Checkov.
2. `plan`: OpenTofu plan through the read-only OIDC role on pull requests. Fork pull requests receive no credentials.
3. `build`: build the image, scan with a pinned Trivy, push to ECR through the push role.
4. `deploy`: apply by image digest from a protected environment after your approval.
5. `pages`: build and deploy the React site to GitHub Pages with GitHub's built-in token.
6. `drift` (nightly): plan and open an issue if infrastructure differs. Never auto-apply.
7. `codeql`: scan Python and TypeScript.

**Repository hygiene**
- Every action is pinned to a full commit SHA with a version comment.
- Default `permissions: contents: read`. Each job asks for only what it needs.
- Concurrency groups and job timeouts on every workflow.
- Branch protection and required status checks, managed by OpenTofu.
- GitHub secret scanning with push protection enabled.

**Dependabot (chosen over Renovate for this size)**
- Ecosystems: GitHub Actions, OpenTofu (`terraform` setting), pip, npm, Docker.
- Weekly updates, grouped, with a cooldown so brand-new releases wait a few days.
- Check: how it treats SHA-pinned actions, and OpenTofu 1.8 or later compatibility.
- Switch to Renovate only if the pull-request noise becomes a problem.

## 5. Secrets model

- **Nothing sensitive stored in GitHub.** AWS access uses short-lived OIDC tokens. GitHub Pages deploys with the built-in token.
- **Local secrets** live in a gitignored `.env`. The repo contains only `.env.example`.
- **Prevent leaks:** Gitleaks in pre-commit and CI, plus GitHub push protection.
- **Confidential content:** a private denylist file kept outside the repo, checked by a local hook. Generic patterns (ticket IDs, internal hosts) are checked in CI.
- **State:** private S3 bucket with encryption, versioning and public access blocked. State holds no secrets because none are managed.
- **Runbook:** how to rotate every credential and what to do after a suspected leak.
- **Not used:** OpenTofu native state encryption, because CI would need a decryption key stored as a secret. Revisit later.

## 6. Cost model and guardrails

| Item | Expected cost |
|---|---|
| GitHub (repo, Actions, Pages, scans) | $0 (public repo, verify) |
| Lambda, Function URL | $0 inside the always-free allowance |
| DynamoDB (optional) | $0 inside the always-free allowance |
| CloudWatch Logs | $0 with 7-day retention and low volume |
| S3 state bucket | A fraction of a cent a month (estimate) |
| ECR image storage | **A few cents a month.** Private image storage is billed per GB-month. A lifecycle policy keeps 2 images, and a slim image keeps each small |
| Domain (optional) | About $10.46 a year at Cloudflare (third-party price) |

**Guards (AWS has no hard cap)**
- A $1 Budget and Cost Anomaly Detection, created before anything else.
- Lambda reserved concurrency of 1 or 2. Check that the account's concurrency quota allows it.
- Small memory, short timeout, no provisioned concurrency.
- A policy allowlist that blocks NAT gateways, load balancers, managed databases and out-of-region resources.
- A documented kill switch: Level 1 teardown (`just teardown-api`) in section 6a.
- Run `tofu destroy` on any short-lived test resources.

## 6a. Teardown and shutdown

The deployment is meant to run only while the demo is needed, so a clean teardown is a first-class feature, rehearsed before launch. The repository stays useful afterwards as a code showcase.

**Three levels**

| Level | When | Removes | Keeps | How |
|---|---|---|---|---|
| 1. Pause the API | When the API is not needed, or at any cost scare | The `prod` root: Lambda, Function URL, ECR repo and images, DynamoDB, log groups | The GitHub Pages site (shows "API offline" with the saved copy), the bootstrap and the GitHub settings | `just teardown-api` |
| 2. Remove AWS | When the demo is no longer needed | Level 1, then the `bootstrap` root: state bucket, OIDC provider and roles, Budget, anomaly monitor | The repository and the static site | `just teardown-aws` |
| 3. Retire the project | When you are done | Level 2, then the site | An archived public repo with a README banner (optional), or nothing | Checklist in the runbook |

**Design rules that make teardown clean (build these in from the start)**
- Tag every AWS resource `Project=portfolio` and use one naming prefix.
- Create nothing by hand in the console. Anything created manually is listed in the runbook.
- The ECR repository uses `force_delete`, and the state bucket uses `force_destroy` (this must also remove old object versions). Both are switched on by a variable only when tearing down.
- Manage the Lambda log group in OpenTofu. Otherwise Lambda recreates an unmanaged log group that survives `destroy`.
- The GitHub repository resource has `prevent_destroy`. Destroying the `github` root must never delete the repository.
- The OIDC provider is shared across the account. Delete it only if this project created it and nothing else uses it.
- The bootstrap root is destroyed last and only from a local authenticated session, because it holds the identities that CI uses.

**Order of operations for Level 2**
1. Preview with `tofu plan -destroy` in the `prod` root and read it.
2. Destroy the `prod` root (Level 1).
3. Run `just verify-clean` and check that nothing tagged `Project=portfolio` remains except the bootstrap.
4. Migrate the bootstrap state back to local. This must happen before the state bucket is destroyed.
5. Destroy the bootstrap root, including the Budget and the anomaly monitor, which are removed last.
6. Delete any local AWS profile or credentials used for the bootstrap. No AWS keys exist in GitHub.
7. Run `just verify-clean` again, then check Cost Explorer and the bill the next day for new charges.

**`just verify-clean`** runs read-only AWS CLI checks for Lambda functions, ECR repositories, DynamoDB tables, S3 buckets, CloudWatch log groups, IAM roles and OIDC providers, and Budgets. It also does a tag search for `Project=portfolio`.

**GitHub and the domain after teardown**
- Disable the nightly drift workflow, so scheduled runs do not fail against a removed backend.
- Add a README banner: "Deployment torn down on <date>. Recreate with `just up-prod`."
- The site can stay up as a static version. Or take Pages down.
- If you bought a domain, turn off auto-renew and remove the DNS records. A domain is a yearly cost.

**Rebuild path**
The documented sequence is bootstrap, then `github`, then `prod`. Rehearse it once before launch, so you know it works and how long it takes.

## 7. Repository layout

```
portfolio/
  app/            FastAPI service, tests, Dockerfile
  web/            React app
  content/        schema and public-safe content (no private sources)
  infra/
    bootstrap/  github/  prod/  modules/
  policies/       OPA/Conftest rules
  docs/           architecture, secrets model, runbooks, decisions
  .github/        workflows, dependabot.yml
  justfile  .gitattributes  .pre-commit-config.yaml  .env.example  README.md  SECURITY.md  LICENSE
```

## 8. Tasks in priority order

Estimates assume focused work. "Done when" is the acceptance check.

### Must: foundations
| # | Task | Done when | Est. |
|---|---|---|---|
| 1 | Repo and secrets baseline: public repo, MIT license, `.gitignore`, `.gitattributes` (LF endings), `.env.example`, secret scanning with push protection, Gitleaks pre-commit, and the native Windows toolchain installed and documented | A planted fake secret is blocked; `just --list` runs in Git Bash | 0.75 d |
| 2 | CI skeleton: read-only permissions, SHA-pinned actions, `actionlint`, `zizmor`, ruff, pytest, required checks | Green on a PR; an unpinned action fails | 1 d |
| 3 | Dependabot for actions, OpenTofu, pip, npm, Docker, with a cooldown | First update PRs appear | 0.25 d |
| 4 | Code scans: CodeQL, Checkov, dependency review | A deliberate bad change fails CI | 0.5 d |

### Must: OpenTofu and AWS
| # | Task | Done when | Est. |
|---|---|---|---|
| 5 | AWS preflight: review the bill, MFA on root, no root keys, a $1 Budget, Cost Anomaly Detection | Billing shows a $0 baseline | 0.25 d |
| 6 | Bootstrap root: S3 state with native locking, OIDC provider, `plan` and `ecr-push` roles, permission boundary. Tag everything `Project=portfolio`, with `force_destroy` behind a variable. Run once from an authenticated session, then migrate state | `tofu init` works from a clean clone; no AWS keys exist; bootstrap state is not committed; `tofu plan -destroy` shows the whole bootstrap would be removed | 1.5 d |
| 7 | OpenTofu manages the GitHub repo: branch protection, required checks, security features, Pages, environments. The repository itself has `prevent_destroy` | A settings change by PR shows a plan diff; a destroy plan does not include the repository | 1 d |
| 8 | CI plan job through OIDC; forks get no credentials; apply needs approval in a protected environment | Plan appears on PRs | 1 d |

### Must: the application
| # | Task | Done when | Est. |
|---|---|---|---|
| 9 | Content: sanitized CV data (approved line by line), a schema, leak checks (patterns plus a private denylist) | Checks pass, and fail on planted violations | 1.5 d |
| 10 | FastAPI skeleton: `/health`, `/content`, Pydantic models, pytest, ruff, a type checker | Tests pass | 1 d |
| 11 | Dockerfile for the API (multi-stage, slim, non-root, health check) and a Compose file. Docker runs only in CI | Hadolint passes locally; the CI job builds the image and the Compose stack answers `/health` | 1.25 d |
| 12 | React app: renders `/content`, timeline, skills filter, saved-copy fallback when the API is offline | Works with the API on and off | 2 d |
| 13 | Deploy the React site to GitHub Pages | Live URL | 0.5 d |

### Must: production on AWS
| # | Task | Done when | Est. |
|---|---|---|---|
| 14 | `prod` root: ECR (keep 3 images, `force_delete` behind a variable), Lambda container image with the Lambda Web Adapter, Function URL, least-privilege role, optional reserved concurrency, a managed log group with 7-day retention, all tagged `Project=portfolio`. Done in three slices (D34): **14a** the root and the apply-role permissions, **14b** the build-and-push slice of task 15 (an image cannot exist before a workflow on `main` builds one), **14c** apply the Lambda by digest, prove it, rehearse destroy and recreate | The API answers on the Function URL; `tofu destroy` removes everything and `apply` recreates it | 2 d |
| 15 | CI/CD: build the image, scan with Hadolint and a pinned Trivy, push to ECR via OIDC, deploy by digest after approval | A merge produces a scanned image you can approve to deploy | 1.5 d |
| 15a | Releases (added after task 10): one version source (`APP_VERSION` and `GIT_SHA`, set by the build from the git tag), a tag-driven workflow that builds the image and creates a GitHub Release with generated notes, the image tagged with the version and deployed by digest. No `release-please`: a pull request opened with `GITHUB_TOKEN` does not run the required checks, and a personal token would be a stored secret | Pushing a `vX.Y.Z` tag produces a GitHub Release whose image reports that version and SHA on `/health` | 0.75 d |
| 16 | API hardening: CORS locked to the site origin, request size limits, security headers, no secrets in the image | CORS and header tests pass | 0.5 d |
| 17 | Smoke tests: end-to-end against the Compose stack in CI (the only place Docker runs), and a post-deploy health check | Fails loudly when something is down | 1 d |
| 18 | Cost guards verified: Budget alert tested, reserved concurrency confirmed | A test alert reaches you | 0.5 d |
| 18a | Teardown scripts and runbook: `just teardown-api`, `just teardown-aws`, `just verify-clean`, the Level 1 to 3 procedure, and the manual steps (GitHub, domain, credentials) | Level 1 works end to end and the checks pass; Level 2 is dry-run with `plan -destroy` | 1 d |

### Must: finish
| # | Task | Done when | Est. |
|---|---|---|---|
| 19 | README with architecture diagram and badges, the About this project page, and a "how secrets work here" page | A reviewer understands it in 60 seconds | 1 d |
| 20 | Stability pass: pinned tool versions, caching, 10 green CI runs in a row | No flaky runs | 0.5 d |
| 20a | Teardown and rebuild rehearsal: run Level 1, rebuild `prod`, then run the full Level 2 once on a clean run and verify nothing is left; time it | `verify-clean` passes, the bill shows no new charges the next day, and the rebuild steps in the runbook are correct | 0.5 d |
| 20b | End-of-life checklist: README banner text, turn off auto-renew and remove DNS if a domain exists, disable the drift workflow, decide whether to archive the repo | Checklist committed to `docs/` | 0.25 d |

### Should
| # | Task | Done when | Est. |
|---|---|---|---|
| 21 | `/contact` endpoint into DynamoDB (validation, size limit, honeypot, 90-day TTL, Moto tests, privacy note on the form) | A message is stored and expires | 1 d |
| 22 | Nightly drift detection that opens an issue | A manual change triggers an issue | 0.5 d |
| 23 | Three OPA/Conftest rules, including the cost-risk allowlist | A violating change fails CI | 0.5 d |
| 24 | Image signing with cosign and a software bill of materials | `cosign verify` works | 0.5 d |
| 25 | OpenSSF Scorecard badge | Badge on README | 0.25 d |
| 26 | Secrets rotation and incident runbook | Documented and tested once | 0.25 d |

### Could
- UI/UX elevation pass (added in task 12, after task 20): visual design, motion and a print stylesheet on top of the design tokens, with Playwright visual-regression tests against the built site. Task 12 prepares for it (D29, D30): styling goes through tokens and logical properties, components take data as props and render without browser globals, and the page metadata comes from the content. None of that blocks a later redesign.
- Custom domain with Cloudflare DNS in OpenTofu, plus a secret header the API checks.
- OpenTofu native state encryption.
- Renovate instead of Dependabot, and release-please.

**Totals:** about 22 days for the must items, about 25 with the should items (task 15a added).
**Cut line:** if you are behind after task 13, ship tasks 1 to 13, 19 and 20 as a working local plus static-site version, and do production (tasks 14 to 18) as a separate milestone.

## 9. Local development and testing

- **No local Docker.** The machine runs Windows without WSL, so containers run only in GitHub Actions. If you later want Docker locally, install WSL2 or use GitHub Codespaces. Neither is needed for this plan.
- **Native toolchain:** Git for Windows (Git Bash), Python with `uv`, Node, OpenTofu, Gitleaks, `actionlint`, `pre-commit`, `just`.
- **API:** run it natively with `uvicorn`. Python tests use pytest, with Moto in place of DynamoDB. There is no AWS emulator server.
- **Web:** `npm run dev` for development and vitest for tests. Playwright is optional.
- **OpenTofu:** `fmt`, `validate` and `test` with mock providers run locally and need no credentials.
- **Container checks in CI only:** image build, Hadolint (also available natively), Trivy scan, and the Compose smoke test.
- **Windows hygiene:** a `.gitattributes` that forces LF line endings, forward slashes in scripts, and scripts written for Git Bash.
- **Credentials:** local runs use no AWS credentials. `tofu plan` against real AWS runs only in CI through the read-only OIDC role. Local credentials are used only for the one-time bootstrap in task 6.

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Unexpected AWS charges (no hard cap) | Section 6 guards, small resource limits, kill switch |
| Public Function URL called directly | CORS lock, reserved concurrency cap, optional Cloudflare secret header |
| Confidential content published | Public-safe content only, leak checks, private denylist, review before every merge |
| Compromised CI or a third-party action | SHA pins, read-only default permissions, OIDC trust limited to this repo, no credentials for forks, Dependabot cooldown |
| Scanner supply-chain incident (Trivy, March 2026) | Pin scanner versions and actions by SHA |
| Free-tier or policy changes | Re-verify limits, keep `prod` destroyable, keep the static site working without the API |
| A teardown leaves billable leftovers (a log group, an object version, an ECR image, a forgotten resource) | Tag everything, create nothing by hand, run `just verify-clean` before and after, rehearse once, and check the bill the next day |
| `destroy` removes something it should not (the GitHub repo, a shared OIDC provider) | `prevent_destroy` on the repo, delete the OIDC provider only if this project created it, always read `plan -destroy` first |
| Docker problems only show up in CI, so feedback is slower | Keep the Dockerfile simple, run Hadolint natively in pre-commit, make small changes, and run the container job on every branch push. Codespaces or WSL2 are fallbacks |
| Scope creep | Follow the priority order and the cut line |

## 11. Not verified. Check before relying on it

- Lambda, DynamoDB and CloudWatch free-tier limits for this account, and the account's Lambda concurrency quota (needed for reserved concurrency).
- That a Lambda container image can be used only from a private ECR repository in the same region.
- That the Lambda Web Adapter works with the chosen FastAPI setup.
- Dependabot support for OpenTofu (announced December 2025) and its handling of SHA-pinned actions.
- Free CodeQL, secret scanning and push protection on public repositories.
- S3 native state locking in the OpenTofu version you use.
- Cloudflare details if you add a domain: price, and whether a secret header works with a Function URL.
- That a tag search finds every resource type this project uses, and that `force_destroy` on the versioned state bucket removes old object versions.
- That Gitleaks, `actionlint`, OpenTofu and `just` all run well natively on your Windows version, and that Git Bash handles the scripts.

## 12. Definition of done

A reviewer sees, within 60 seconds:
1. A README with the premise, an architecture diagram, and a plain statement of what runs where.
2. A live site that still works when the API is down.
3. A green CI with scans and a visible release.
4. An About this project page explaining the over-engineering and the cost model.
5. No secrets anywhere in the repository or in GitHub.
6. A documented, rehearsed teardown that removes everything in minutes, and a rebuild path.

## 13. How to describe it truthfully

- Built a deliberately over-engineered portfolio to extend my skills into OpenTofu, AWS and React: a Python (FastAPI) and React app running as a Docker container on AWS Lambda.
- Managed the GitHub repository and AWS infrastructure with OpenTofu: remote state, keyless GitHub OIDC login, least-privilege roles, drift detection and policy checks.
- Hardened the delivery pipeline: SHA-pinned actions, code and image scans, secret scanning with push protection, Dependabot, and no long-lived credentials stored in GitHub.

Do not claim production AWS experience beyond this personal project.

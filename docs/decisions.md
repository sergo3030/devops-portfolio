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
| D12 | Trust policies use the immutable subject format `repo:OWNER@OWNER_ID/REPO@REPO_ID:...` | Repositories created after 2026-07-15 use it. The `pull_request` form is inferred and verified in task 8 |

| D13 | Local bootstrap identity is the IAM user `portfolio-admin` (MFA, no keys) with `aws login` | Temporary credentials, no stored keys. Root stays unused. Needed again for teardown and the rebuild rehearsal |
| D14 | Reserved concurrency cannot be set: the account's Lambda concurrent executions quota is 10 | AWS requires about 100 unreserved. The quota is adjustable. The limit of 10 acts as a natural cap while it stays low. See open items |

| D15 | The repository went public on 2026-10-21, in two applies (visibility, then secret scanning and push protection) | GitHub rejects the security settings in the same update as the flip. The `enable_secret_scanning` variable controls the second step |

| D16 | Branch protection is a ruleset with no bypass actors. Break-glass is `ruleset_enforcement=disabled` applied from the laptop | The rules bind the owner too. The escape hatch is code, so it is reviewable and rehearsed |
| D17 | Only GitHub-owned actions plus an allowlist may run, and every action must be SHA-pinned (enforced by GitHub, not only by zizmor) | Supply-chain control. A new action is a reviewed change to `allowed_action_patterns` |
| D18 | Fork PR approval and private vulnerability reporting are set with `gh api` and checked by `just github-settings-check` | No provider resource exists for them |

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

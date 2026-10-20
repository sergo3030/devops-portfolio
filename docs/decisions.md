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

## Open items (decided when the task that needs them starts)

| Item | Task | Issue |
|---|---|---|
| Read-only `plan` role versus S3 native locking | 6, 8 | `tofu plan` writes a lock object. Allow `PutObject` and `DeleteObject` on the lock key only, or plan with `-lock=false` |
| The `github` root needs a GitHub token | 7, 8, 22 | `GITHUB_TOKEN` cannot administer repository settings. Plan and apply that root locally, and let CI plan only `prod` |
| Missing `apply` role in task 6 | 6 | Section 3 of the plan defines it, task 6 does not list it |
| Credentials for the one-time bootstrap | 6 | Prefer short-lived credentials (`aws login`) over stored access keys. Verify against the current AWS CLI docs first |
| Reserved concurrency needs the account limit minus 100 | 5, 14 | Check the real quota with `aws lambda get-account-settings`. New accounts have lower quotas |
| Image format on Lambda | 15 | Build with provenance attestations off, so Lambda accepts the manifest |
| Budget alert email address | 6, 18 | Pass through a gitignored tfvars or `TF_VAR_*`, never in the repository |
| Branch protection, required-reviewer environments, Pages on a private repository | 7, 8, 13 | Not listed for the Free plan. Confirm through the API, or wait for the go-public step |
| Tools pinned inline in workflows (`zizmor`, `actionlint-py`, `check-jsonschema`, `checkov`, uv) | 20 | Dependabot does not update them. Move them into a tracked manifest or accept manual bumps |

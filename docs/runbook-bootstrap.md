# Runbook: bootstrap root

The `infra/bootstrap` root creates what every other root depends on: the state
bucket, the GitHub OIDC provider, the CI roles, the permission boundary, and the
cost guards. It is applied from a local session, never from CI.

## Prerequisites

- AWS CLI 2.32.0 or newer, OpenTofu 1.10 or newer
- An IAM user for local admin work (`portfolio-admin`): MFA, console password,
  `AdministratorAccess` and `SignInLocalDevelopmentAccess`, **no access keys**
- `TF_VAR_budget_alert_email` set in your user environment (never in the repo)

## Log in (temporary credentials, up to 12 hours)

```bash
aws login --profile portfolio-bootstrap
```

Choose **IAM user** in the browser, not an open root session. Verify with
`aws sts get-caller-identity --profile portfolio-bootstrap`: the ARN must end in
`user/portfolio-admin`. Credentials are cached under `~/.aws/login/cache`. Run
`aws logout --profile portfolio-bootstrap` when done.

## First apply (empty account)

The state bucket does not exist yet, so the first apply uses a local backend.

1. Make sure `infra/bootstrap/backend.tf` does not exist (on a rebuild, move it away).
2. In `infra/bootstrap`: `tofu init`, then `tofu plan -out=tfplan`. Read the plan.
3. `tofu apply tfplan`. Expect 16 resources.
4. Restore `backend.tf`, then `tofu init -migrate-state -force-copy`.
5. Confirm the state object exists in the bucket and `tofu plan` reports no changes.
6. Delete `terraform.tfstate*` and `tfplan`. They are gitignored and hold the alert email.

Set `AWS_PROFILE=portfolio-bootstrap` and `AWS_REGION=us-east-1` in the shell first.

## Day-to-day

`tofu plan` and `tofu apply` in `infra/bootstrap` with the same login. CI never
applies this root.

## Changing the alert email or the budget thresholds

CI plans this root with a placeholder email, so the Budget notifications and the anomaly
subscriber are in `ignore_changes`. A normal apply therefore never changes them. To change
the email (set `TF_VAR_budget_alert_email` first) or the thresholds, replace both:

```bash
tofu apply -replace=aws_budgets_budget.monthly -replace=aws_ce_anomaly_subscription.daily
```

Both resources are free and are recreated in seconds.

## Roles

| Role | Trusts (OIDC subject) | Can do |
|---|---|---|
| `portfolio-plan` | pull request of this repository | Read the project's resources, read state, write only `.tflock` objects |
| `portfolio-ecr-push` | push to `main` | Push to the one ECR repository |
| `portfolio-apply` | job in the `prod` environment (needs the owner's approval) | Today: read and write the `prod/` state keys only. Permissions for the prod root come in task 14 |

## How CI uses the roles

| Workflow | Role | When | Notes |
|---|---|---|---|
| `plan.yml` | `portfolio-plan` | Pull requests of this repository that change `infra/bootstrap/**` or `infra/prod/**` (one job per root) | `tofu plan` with a placeholder email. The full plan is in the job log, where the account ID is masked. The job summary shows only the one-line result. Fork pull requests are skipped. |
| `ci.yml`, job `image` | `portfolio-plan` | Pull requests of this repository (not forks) | Only to log in to public ECR, so the adapter image is pulled with the AWS account's limits and not the shared anonymous ones (D40). The step may fail without failing the job. |
| `build.yml` | `portfolio-ecr-push` | Push to `main` and manual runs | Looks up the commit's image, logs in to public ECR (same reason), pushes the image, reads its digest back. |
| `deploy.yml` | `portfolio-apply` | Called by `build.yml` after every image push, or run by hand with a digest, after the owner approves the `prod` environment | Plans the prod root with the digest, checks that the plan only swaps the Lambda image, applies that exact plan, and checks `/health` (see the prod runbook, "Deploying"). |

The workflows read the account ID from the Actions secret `AWS_ACCOUNT_ID` (masked in
logs by GitHub, see decision D19). If a plan
fails with `AccessDenied`, a read action is missing from the plan role: add it to
`roles.tf`, apply the bootstrap root locally, and re-run the job.

## Teardown (Level 2, last step)

Only after the `prod` root is destroyed and `just verify-clean` is clean.

1. Move the state back to local: remove `backend.tf`, then `tofu init -migrate-state -force-copy`.
2. Re-apply once with `-var force_destroy=true` so the bucket can be emptied on destroy.
3. `tofu plan -destroy`, read it, then `tofu destroy`.
4. If the OIDC provider existed before this project, set `create_oidc_provider = false`
   first. The provider is account-wide.
5. `aws logout --all`. Delete `portfolio-admin` only if you are leaving the project for good.

## Known limits

- The Resource Groups Tagging API does not list IAM roles. `verify-clean` must also
  list roles by the `portfolio-` name prefix.
- The OIDC subject formats are verified (see decisions.md). They contain the owner and
  repository names as well as the IDs, so after a rename or transfer re-read the claims and
  update `github_owner` and `github_repo` in the bootstrap variables.
- Lambda concurrent executions is 10 on this account (see decisions.md).

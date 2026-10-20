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
- The `pull_request` OIDC subject format is inferred and is verified in task 8.
- Lambda concurrent executions is 10 on this account (see decisions.md).

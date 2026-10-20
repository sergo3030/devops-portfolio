# Manual steps (done by hand, outside OpenTofu)

Everything created or changed by hand is listed here, so teardown and rebuild
have no surprises. The rule is "create nothing by hand in the console". These
are the exceptions, with the reason.

## AWS account (one-time, console)

| Date | Step | Why by hand | Teardown impact |
|---|---|---|---|
| 2026-10 | Root user: MFA enabled, no access keys (both verified) | Root is not manageable as code | None. Keep. |
| 2026-10 | Removed an old, unused admin IAM user and its access key | It was abandoned, with no activity for almost three years | None. Nothing to restore. |
| 2026-10 | IAM user `portfolio-admin` created: MFA, console password, `AdministratorAccess` and `SignInLocalDevelopmentAccess`, no access keys | Someone has to exist to run the one-time bootstrap. Used with `aws login` (temporary credentials) | Kept for rebuilds and Level 2 teardown. Delete it only when leaving the project for good |

Preflight results (task 5): no root access keys, no charges in the last three
months ($0 baseline). Lambda concurrent executions quota: 10 (task 6).

## GitHub (account level)

| Step | Why by hand |
|---|---|
| Repository created as private, then made public at the go-public step | Bootstrapping: the repo must exist before OpenTofu can manage it (task 7) |
| Account setting "Block command line pushes that expose my email" (to do, in github.com/settings/emails) | Account settings are not exposed by the API or the provider |

## Rule for new entries

Add a row here in the same pull request that introduces any manual step, with the
reason and what teardown must do about it.

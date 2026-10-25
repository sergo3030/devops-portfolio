# How secrets work here

The short version:

- **There is no long-lived AWS credential anywhere.** GitHub Actions proves who it is with a
  short-lived OpenID Connect (OIDC) token, and AWS hands out credentials that last at most an hour.
- **One GitHub Actions secret exists**, `AWS_ACCOUNT_ID`, and it is not a credential. It is a secret
  only so that GitHub masks it in public logs.
- **Things that must stay private are kept outside the repository**: the alert email address and the
  list of terms that must never appear on the site.
- **Several independent layers look for secrets** before, during and after a commit.

Every statement below says where to check it. The live GitHub settings were read on 2026-10-25.

## What exists

| What | Where it lives | Why it is safe | How to check |
|---|---|---|---|
| AWS access for CI | Nowhere. Each job gets an OIDC token and trades it for a session of at most one hour | No key can leak or be rotated because none is stored. Three roles, each trusting exactly one kind of job (see below) | [`infra/bootstrap/roles.tf`](../infra/bootstrap/roles.tf), [`infra/bootstrap/oidc.tf`](../infra/bootstrap/oidc.tf) |
| AWS access for the owner | An IAM user with MFA and **no access keys**, used through `aws login` (temporary credentials), logged out after each task | Nothing long-lived on the laptop; the user is not the root user | [`manual-steps.md`](manual-steps.md), [`runbook-bootstrap.md`](runbook-bootstrap.md) |
| GitHub Actions secrets | One: `AWS_ACCOUNT_ID`. No variables | The account number is needed to name a role. It is not a credential, but only secrets are masked in logs (D19), and a CI check fails if a workflow takes it from a variable or contains a literal role ARN | `gh secret list`; the check is the step "Account ID must come from the masked secret" in [`ci.yml`](../.github/workflows/ci.yml) |
| The `GITHUB_TOKEN` of workflows | Created per run | Read-only by default (`contents: read` at the top of every workflow); jobs ask for more only where they need it (`id-token: write` to get the OIDC token, `pages: write` to publish). Workflows cannot approve pull requests | Repository settings, Actions, General; each workflow's `permissions:` block |
| The Budget alert email | An environment variable on the owner's machine (`TF_VAR_budget_alert_email`) | CI plans with a placeholder address and the notification blocks ignore changes (D20), so the address is never in a file or a log | [`infra/bootstrap/cost_guards.tf`](../infra/bootstrap/cost_guards.tf), [`runbook-bootstrap.md`](runbook-bootstrap.md) |
| The private content denylist | `~/.portfolio/denylist.txt` on the owner's machine | It lists the names the site must not contain, so it cannot be in the repository. It runs in the pre-commit hook; CI cannot run it and says so | [`content.md`](content.md) |
| Secrets in the running API | None. The function has no environment variables, its role can write only its own log group, and the image sets only the public site origin | There is nothing to steal from the container | [`infra/prod/lambda.tf`](../infra/prod/lambda.tf), [`infra/prod/iam.tf`](../infra/prod/iam.tf), [`api.md`](api.md) |
| The function URL | Public, in the site's JavaScript | It is an address, not a secret. CORS only stops other websites' scripts, so what really limits abuse is the concurrency cap, read-only requests and the emergency brake (see [cost guards](runbook-prod.md#cost-guards-and-how-each-was-tested-task-18-d47)) | [`api.md`](api.md#hardening-task-16-d43) |

## Who can become which AWS role

| Role | Trusts only | Can do | Extra gate |
|---|---|---|---|
| `portfolio-plan` | A pull request of this repository, or a push to `main` | Read the project's resources and the state; write only the lock object. Also log in to public ECR for authenticated pulls (D40, D49) | Pull requests from forks are skipped |
| `portfolio-ecr-push` | A push to `main` | Push images to the one ECR repository | Cannot run from a branch |
| `portfolio-apply` | A job in the `prod` environment | Change the production stack, and nothing else | The `prod` environment requires the owner's approval and is limited to the `main` branch |

All three carry a **permission boundary**: only the services this project uses, one region, and
explicit denies for the expensive families (EC2, load balancers, databases, API Gateway and so on).
The apply role may only create roles that carry the same boundary, so it cannot raise its own
privileges. The trusted OIDC subjects (they contain the repository's numeric IDs, so a renamed or
re-created repository does not match) are listed in [`decisions.md`](decisions.md#verified-oidc-subject-formats-2026-10-21).
Tests that run with no AWS account pin all of this:
[`infra/bootstrap/tests/bootstrap.tftest.hcl`](../infra/bootstrap/tests/bootstrap.tftest.hcl).

## The layers that look for a leaked secret

| Layer | When | What it does |
|---|---|---|
| gitleaks pre-commit hook | Before a commit exists | Scans the staged changes ([`.pre-commit-config.yaml`](../.pre-commit-config.yaml)) |
| gitleaks in CI | Every pull request and push | Scans the full git history, with the binary pinned by checksum (job `secrets (gitleaks)`) |
| GitHub secret scanning and push protection | On push | Enabled on the repository (`gh api repos/sergo3030/devops-portfolio --jq .security_and_analysis`, needs admin) |
| Content checks | Every commit that touches the content | Patterns for key material, emails, account IDs, internal names and numbers; the private denylist locally ([`content.md`](content.md)) |
| `.dockerignore` allowlist | Every image build | Nothing enters the build context unless it is listed, so no `.env`, key or git history can get into the image |
| Container smoke test | Every image build | Fails if the image sets a secret-looking variable, contains a secret-looking file, or holds more than the app and its content ([`scripts/smoke-test-container.sh`](../scripts/smoke-test-container.sh)) |
| Trivy secret scan | Every image build, before the push | Fails the build on a secret in the image ([`scripts/scan-image.sh`](../scripts/scan-image.sh)) |

Supply-chain controls that protect the secrets above: every action is pinned to a full commit SHA and
GitHub enforces it, only a short list of non-GitHub actions is allowed, `zizmor` and `actionlint`
check the workflows, Dependabot keeps dependencies current, and dependency review gates new ones.

## If something leaks

| What leaked | What to do |
|---|---|
| An AWS credential | There is none to leak from the repository. A CI session expires within the hour. For the owner's session, `aws logout` and sign in again |
| The account ID | It is not a credential. It appeared once in a public run log before D19; that log was deleted and the workflow now uses a secret |
| The alert email | Change it and replace the two cost-guard resources (see [`runbook-bootstrap.md`](runbook-bootstrap.md#changing-the-alert-email-or-the-budget-thresholds)) |
| A term from the denylist on the site | Remove the line, add the term to the denylist, and republish; the next commit is checked against it |
| Something unknown, or the GitHub account | Level 1 teardown pauses the API in minutes ([`runbook-prod.md`](runbook-prod.md#teardown-three-levels-task-18a-d48)); the emergency brake stops all requests |

## What this does not protect

Stated plainly, because a security page that lists only strengths is not credible:

- **The GitHub account.** The `prod` environment requires an approval, but there is one maintainer
  and self-review is allowed, so the approval is a deliberate pause, not a second person. The account
  is protected by its own sign-in security, not by this repository.
- **The owner's machine during a login.** An admin session lasts until it is logged out or expires,
  and any program on the machine could use it then. The practice is to log in for a task and log out.
- **Tools downloaded by workflows.** gitleaks, Trivy and hadolint are pinned by checksum, but a few
  tools pinned inline are not tracked by Dependabot, so a bump is manual (planned for task 20).
- **A public, unauthenticated API.** Anyone can call it. It serves only public content, accepts
  nothing, and is capped, but it can be made to run, so it is a cost risk, not a data risk.
- **Alerts that arrive late.** AWS Budget emails lag by hours; the cap and the brake are the defence.

## How to look for yourself

```bash
gh api repos/sergo3030/devops-portfolio --jq .security_and_analysis        # needs admin
gh secret list                                                             # names only, needs admin
grep -rn "secrets\." .github/workflows                                     # the only secret any workflow reads
grep -rn "id-token: write" .github/workflows                               # which jobs may ask for AWS credentials
```

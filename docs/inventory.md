# Inventory: how to find everything that belongs to this project

Use this to audit the project, or to check that a teardown left nothing behind.
The account ID is deliberately not written here. Read it with
`aws sts get-caller-identity --query Account --output text`.

## AWS (region `us-east-1`)

Log in first: `aws login --profile portfolio-bootstrap` (IAM user, not root).

| What | Console | Command line |
|---|---|---|
| Everything tagged `Project=portfolio` | Resource Groups & Tag Editor, then Tag Editor: region `us-east-1`, all resource types, tag `Project` = `portfolio`, Search | `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=portfolio` |
| IAM roles (the tag search never lists them) | IAM, Roles, search `portfolio-` | `aws iam list-roles --query "Roles[?starts_with(RoleName,'portfolio-')].RoleName"` |
| IAM policies | IAM, Policies, search `portfolio-` | `aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName,'portfolio-')].PolicyName"` |
| OIDC provider for GitHub | IAM, Identity providers | `aws iam list-open-id-connect-providers` |
| IAM users (should be only the admin user, with no keys) | IAM, Users | `aws iam list-users` and `aws iam list-access-keys --user-name <name>` |
| S3 state bucket `portfolio-tfstate-*` | S3, buckets | `aws s3api list-buckets` |
| Budget `portfolio-monthly-*` | Billing and Cost Management, Budgets | `aws budgets describe-budgets --account-id <account-id>` |
| Anomaly monitor and subscription | Billing and Cost Management, Cost Anomaly Detection | `aws ce get-anomaly-monitors` and `aws ce get-anomaly-subscriptions` |
| Later (task 14): ECR repository, Lambda function, log group, optional DynamoDB table | ECR, Lambda, CloudWatch Logs groups, DynamoDB | `aws ecr describe-repositories`, `aws lambda list-functions`, `aws logs describe-log-groups --log-group-name-prefix /aws/lambda/portfolio`, `aws dynamodb list-tables` |
| Quota request (Lambda concurrent executions) | Service Quotas, AWS Lambda | `aws service-quotas list-requested-service-quota-change-history-by-quota --service-code lambda --quota-code L-B99A9384` |

The managed resources are authoritative in state: run `tofu state list` in
`infra/bootstrap` (and in `infra/prod` once it exists).

To see spend by project in Cost Explorer, first activate the `Project` cost
allocation tag in Billing, Cost allocation tags. Activation takes up to 24 hours.

## GitHub

- Repository `sergo3030/devops-portfolio`: pull requests, Actions runs,
  Dependabot, and the settings managed by `infra/github` (`tofu state list` there).
- Closed throwaway pull requests stay visible in the history. Closed pull requests cannot be deleted.

## On the laptop

| What | Where |
|---|---|
| Checkout | `C:\dev\devops-portfolio` |
| Installed tools | GitHub CLI, uv, Python 3.13, Node.js LTS, OpenTofu, gitleaks, actionlint, just, pre-commit, AWS CLI (see `docs/toolchain.md`) |
| User environment variables | `UV_PYTHON_INSTALL_DIR`, `UV_TOOL_DIR`, `TF_VAR_budget_alert_email` |
| AWS login cache and profile | `%USERPROFILE%\.aws\login\cache` and `[profile portfolio-bootstrap]` in `%USERPROFILE%\.aws\config`. Remove with `aws logout --profile portfolio-bootstrap` |
| Provider cache | `C:\dev\.tofu-plugin-cache` (set with `TF_PLUGIN_CACHE_DIR`) |

## Things created by hand

See [manual-steps.md](manual-steps.md). `just verify-clean` (task 18a) will run the
AWS checks above in one command.

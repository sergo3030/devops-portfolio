# Runbook: prod root

`infra/prod` holds what runs in production: the ECR repository, the log group, the Lambda
execution role and, once an image digest is given, the Lambda function with its Function URL.
State: `s3://portfolio-tfstate-x7k2m9qd4t/prod/terraform.tfstate`. Everything is tagged
`Project=portfolio`, `Root=prod`.

| File | Manages |
|---|---|
| `ecr.tf` | Repository (immutable tags, scan on push, `force_delete` behind a variable) and the lifecycle policy that keeps the newest 3 images |
| `logs.tf` | The function's log group, 7-day retention (managed, so `destroy` removes it) |
| `iam.tf` | Execution role `portfolio-prod-lambda` (permission boundary, writes its own log group only) |
| `lambda.tf` | Function (container image by digest), Function URL (auth NONE) and the two public-invoke statements. All four exist only while `image_digest` is set |

## Variables worth knowing

| Variable | Default | Meaning |
|---|---|---|
| `image_digest` | `null` | `sha256:...` of the image to run. `null`: no function and no URL, only the repository and its pieces |
| `reserved_concurrency` | `null` | Parallel-execution cap. `null` = none, because with the default account quota of 10 AWS allows no reservation. Set 1 or 2 once the quota is raised. `0` blocks every request (kill switch) |
| `images_to_keep` | `3` | At least 3, so pushing two newer images before a deploy cannot expire the running one |
| `force_delete_images` | `false` | Teardown only (see below) |

## Applying (locally, with the bootstrap admin session)

```bash
aws login --profile portfolio-bootstrap       # open a terminal tab, sign in as portfolio-admin
export AWS_PROFILE=portfolio-bootstrap AWS_REGION=us-east-1
tofu -chdir=infra/prod init
tofu -chdir=infra/prod plan -out=tfplan        # read it: `tofu show tfplan`
tofu -chdir=infra/prod apply tfplan
rm infra/prod/tfplan
aws logout --profile portfolio-bootstrap
```

1. First apply, no image: repository, lifecycle policy, log group, role and its policy.
2. The `build` workflow pushes an image to the repository and prints its digest (task 14b).
3. Second apply, with the digest: `tofu -chdir=infra/prod plan -var image_digest=sha256:... -out=tfplan`.
   The function URL is in the output `function_url`. Keep it out of the site until task 16.

Pull requests that change `infra/prod/**` run `tofu plan` through the read-only role
(`plan.yml`). It plans with the digest that is deployed now (read from the state output), so the
plan shows only what the pull request changes.

## Public URL: two statements

Since October 2025 a Function URL with no authentication needs both `lambda:InvokeFunctionUrl`
and `lambda:InvokeFunction` in the function's resource policy
([AWS docs](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html)). They are
`aws_lambda_permission.url` and `.invoke`. If the URL answers `403 Forbidden`, check that both
exist (`aws lambda get-policy --function-name portfolio-api`).

## Pausing or removing production (Level 1)

Delete the function but keep the repository: `tofu apply` with `image_digest` unset removes the
function, the URL and both statements. To remove everything:

```bash
tofu -chdir=infra/prod apply -var force_delete_images=true   # lets the repository be deleted with its images
tofu -chdir=infra/prod destroy -var force_delete_images=true
```

Read `plan -destroy` first. The repository holds images, so the first command has to be applied
before the second can delete it. `just teardown-api` wraps this in task 18a.

## Cost and abuse

Normal use costs a few cents a month (ECR storage of 3 images). The URL is public, so a
sustained flood could cost real money before the $1 Budget email reaches anyone: a concurrency
cap only bounds it partly. Until task 16 (CORS, headers) and a raised concurrency quota, the URL
stays out of the site, and `reserved_concurrency = 0` is the emergency brake.

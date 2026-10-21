# Roles assumed by GitHub Actions through OIDC. The `apply` role is created in
# task 8, together with the protected environment whose claim it trusts.

locals {
  oidc_aud_key = "${local.oidc_url}:aud"
  oidc_sub_key = "${local.oidc_url}:sub"
}

# ---------------------------------------------------------------- plan

resource "aws_iam_role" "plan" {
  name                 = "${var.name_prefix}-plan"
  description          = "Read-only `tofu plan` from pull requests of this repository."
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          (local.oidc_aud_key) = "sts.amazonaws.com"
          (local.oidc_sub_key) = "${local.github_sub_prefix}:pull_request"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "plan" {
  #checkov:skip=CKV_AWS_355:Read-only Get/List/Describe actions need Resource "*" for refresh. No write actions except the lock object.
  name = "plan-read-only"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadStateBucketSettings"
        Effect   = "Allow"
        Action   = ["s3:GetBucket*", "s3:GetLifecycleConfiguration", "s3:GetEncryptionConfiguration", "s3:GetAccelerateConfiguration", "s3:GetReplicationConfiguration", "s3:ListBucket", "s3:ListBucketVersions"]
        Resource = local.bucket_arn
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${local.bucket_arn}/*"
      },
      {
        # Native locking writes a lock object next to the state object.
        Sid      = "WriteLockObjectOnly"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.bucket_arn}/*.tflock"
      },
      {
        Sid    = "ReadResourcesManagedByThisProject"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "ecr:Describe*",
          "ecr:List*",
          "ecr:GetLifecyclePolicy",
          "ecr:GetRepositoryPolicy",
          "lambda:Get*",
          "lambda:List*",
          "logs:Describe*",
          "logs:ListTagsForResource",
          "logs:ListTagsLogGroup",
          "dynamodb:Describe*",
          "dynamodb:List*",
          "budgets:ViewBudget",
          "budgets:DescribeBudgetAction*",
          "budgets:ListTagsForResource",
          "ce:GetAnomalyMonitors",
          "ce:GetAnomalySubscriptions",
          "ce:ListTagsForResource",
          "tag:GetResources",
        ]
        Resource = "*"
      },
    ]
  })
}

# ---------------------------------------------------------------- ecr-push

resource "aws_iam_role" "ecr_push" {
  name                 = "${var.name_prefix}-ecr-push"
  description          = "Push images to the one ECR repository, from the main branch only."
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          (local.oidc_aud_key) = "sts.amazonaws.com"
          (local.oidc_sub_key) = "${local.github_sub_prefix}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push-one-repository"
  role = aws_iam_role.ecr_push.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LoginToEcr"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushToOneRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = local.ecr_repository_arn
      },
    ]
  })
}

# ---------------------------------------------------------------- apply

# Assumed only by a job that runs in the protected `prod` environment, which
# needs the owner's approval first. It starts with NO resource permissions: only
# the state of the prod root. The permissions for what the prod root manages
# (ECR, Lambda, logs, its execution role) are added in task 14, next to the code
# that needs them, so this role never holds more than the code in the repository.

resource "aws_iam_role" "apply" {
  name                 = "${var.name_prefix}-apply"
  description          = "Deploys from the protected prod environment, after approval."
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          (local.oidc_aud_key) = "sts.amazonaws.com"
          (local.oidc_sub_key) = "${local.github_sub_prefix}:environment:prod"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "apply" {
  #checkov:skip=CKV_AWS_355:No Resource "*" here: every statement is scoped to the prod state keys.
  name = "apply-prod-state-only"
  role = aws_iam_role.apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListOwnStatePrefix"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.bucket_arn
        Condition = {
          StringLike = { "s3:prefix" = ["prod/*"] }
        }
      },
      {
        # State and its `.tflock` lock object live under the prod/ key prefix.
        Sid      = "ReadWriteProdState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.bucket_arn}/prod/*"
      },
    ]
  })
}

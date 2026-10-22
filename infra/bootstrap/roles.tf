# Roles assumed by GitHub Actions through OIDC. The `apply` role is created in
# task 8, together with the protected environment whose claim it trusts.

locals {
  oidc_aud_key = "${local.oidc_url}:aud"
  oidc_sub_key = "${local.oidc_url}:sub"

  # What a job needs to log in to public ECR (`aws ecr-public get-login-password`), so that image
  # pulls from public.ecr.aws count against this AWS account instead of the shared anonymous limit
  # of the GitHub runners (decisions.md D40). The token only allows pulling public images:
  # pushing to a public registry needs other ecr-public actions, which no role has.
  public_ecr_login_statements = [
    {
      Sid      = "LoginToPublicEcr"
      Effect   = "Allow"
      Action   = "ecr-public:GetAuthorizationToken"
      Resource = "*"
    },
    {
      Sid      = "GetBearerTokenForPublicEcr"
      Effect   = "Allow"
      Action   = "sts:GetServiceBearerToken"
      Resource = "*"
      Condition = {
        StringEquals = { "sts:AWSServiceName" = "ecr-public.amazonaws.com" }
      }
    },
  ]
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
    Statement = concat([
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
    ], local.public_ecr_login_statements)
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
    Statement = concat([
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
    ], local.public_ecr_login_statements)
  })
}

# ---------------------------------------------------------------- apply

# Assumed only by a job that runs in the protected `prod` environment, which
# needs the owner's approval first. It holds the state of the prod root and, since
# task 14, the permissions for exactly what the prod root manages (ECR, Lambda,
# logs, its execution role), so this role never holds more than the code in the
# repository needs. Both live in separate policies below.

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

# What the prod root manages (infra/prod): the ECR repository, the function and its URL, the
# log group, and the function's execution role. Every statement is limited to names that start
# with the project prefix. There is no iam:AttachRolePolicy, so a role can only get inline
# policies, and no iam:PutRolePermissionsBoundary or iam:DeleteRolePermissionsBoundary, so
# the boundary cannot be removed. The role names the policy covers (<prefix>-prod-*) exclude
# plan, apply and ecr-push, so this role cannot change any role of the bootstrap root.
locals {
  prod_function_arn  = "arn:${data.aws_partition.current.partition}:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${var.name_prefix}-*"
  prod_log_group_arn = "arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"
  prod_role_arn      = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-prod-*"
}

resource "aws_iam_role_policy" "apply_prod_resources" {
  #checkov:skip=CKV_AWS_355:The only Resource "*" is logs:DescribeLogGroups, which does not support resource-level permissions. Every other statement names the project's resources.
  #checkov:skip=CKV_AWS_290:Write actions are limited to resources that start with the project prefix, and the apply role is assumable only after the owner's approval.
  #checkov:skip=CKV_AWS_289:The role cannot change permissions of any role outside <prefix>-prod-*, cannot attach managed policies and cannot touch permission boundaries.
  #checkov:skip=CKV_AWS_287:No credentials are exposed: the role only manages resources of the project.
  #checkov:skip=CKV_AWS_286:Privilege escalation is limited to <prefix>-prod-* roles, which are created only with the permission boundary.
  name = "apply-prod-resources"
  role = aws_iam_role.apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageProdRepository"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:ListTagsForResource",
          "ecr:TagResource",
          "ecr:UntagResource",
          "ecr:PutImageTagMutability",
          "ecr:PutImageScanningConfiguration",
          "ecr:PutLifecyclePolicy",
          "ecr:GetLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:GetRepositoryPolicy",
          # Deleting the repository with its images (force_delete) when tearing down.
          "ecr:BatchDeleteImage",
          # Lambda checks that the deploying principal can read the image it is given.
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = local.ecr_repository_arn
      },
      {
        Sid    = "ManageProdLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
          "logs:ListTagsForResource",
          "logs:ListTagsLogGroup",
        ]
        Resource = [local.prod_log_group_arn, "${local.prod_log_group_arn}:*"]
      },
      {
        # DescribeLogGroups does not support resource-level permissions.
        Sid      = "FindLogGroups"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        Sid    = "ManageProdFunction"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PutFunctionConcurrency",
          "lambda:DeleteFunctionConcurrency",
          "lambda:CreateFunctionUrlConfig",
          "lambda:UpdateFunctionUrlConfig",
          "lambda:DeleteFunctionUrlConfig",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:Get*",
          "lambda:List*",
        ]
        Resource = local.prod_function_arn
      },
      {
        # A role may only be created with the project's permission boundary.
        Sid      = "CreateProdRoleWithBoundary"
        Effect   = "Allow"
        Action   = "iam:CreateRole"
        Resource = local.prod_role_arn
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.boundary.arn }
        }
      },
      {
        Sid    = "ManageProdRole"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:TagRole",
          "iam:UntagRole",
        ]
        Resource = local.prod_role_arn
      },
      {
        # Only to the Lambda service, so the role cannot be handed to anything else.
        Sid      = "PassProdRoleToLambda"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.prod_role_arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" }
        }
      },
    ]
  })
}

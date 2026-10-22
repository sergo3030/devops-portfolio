# Runs with a mocked AWS provider: no credentials, no network, no cost.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  # The provider validates ARN syntax, so computed ARNs need realistic values.
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/portfolio-boundary"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_ce_anomaly_monitor" {
    defaults = {
      arn = "arn:aws:ce::123456789012:anomalymonitor/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  budget_alert_email = "alerts@example.com"
}

run "plan_role_trusts_only_pull_requests_of_this_repo" {
  assert {
    condition = (
      jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:sergo3030@61195883/devops-portfolio@1425913518:pull_request"
    )
    error_message = "plan role must trust only the pull_request subject of this repository"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"]
      == "sts.amazonaws.com"
    )
    error_message = "plan role must require the sts.amazonaws.com audience"
  }
}

run "ecr_push_role_trusts_only_the_main_branch" {
  assert {
    condition = (
      jsondecode(aws_iam_role.ecr_push.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:sergo3030@61195883/devops-portfolio@1425913518:ref:refs/heads/main"
    )
    error_message = "ecr-push role must trust only refs/heads/main of this repository"
  }
}

run "ecr_push_is_limited_to_one_repository" {
  assert {
    condition = (
      jsondecode(aws_iam_role_policy.ecr_push.policy).Statement[1].Resource
      == "arn:aws:ecr:us-east-1:123456789012:repository/portfolio-api"
    )
    error_message = "push permissions must name exactly one ECR repository"
  }
}

run "plan_role_cannot_write_state_only_lock_objects" {
  assert {
    condition = (
      jsondecode(aws_iam_role_policy.plan.policy).Statement[2].Resource
      == "arn:aws:s3:::portfolio-tfstate-x7k2m9qd4t/*.tflock"
    )
    error_message = "the only S3 write allowed to the plan role is the lock object"
  }
}

run "all_roles_carry_the_permission_boundary" {
  assert {
    condition     = aws_iam_role.plan.permissions_boundary == aws_iam_policy.boundary.arn
    error_message = "plan role must have the boundary"
  }

  assert {
    condition     = aws_iam_role.ecr_push.permissions_boundary == aws_iam_policy.boundary.arn
    error_message = "ecr-push role must have the boundary"
  }
}

run "state_bucket_is_not_force_destroyed_by_default" {
  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "force_destroy must default to false"
  }

  assert {
    condition     = aws_s3_bucket.state.bucket == "portfolio-tfstate-x7k2m9qd4t"
    error_message = "unexpected state bucket name"
  }
}

run "force_destroy_is_switched_on_by_the_variable" {
  variables {
    force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.state.force_destroy == true
    error_message = "force_destroy variable must reach the bucket"
  }
}

run "existing_oidc_provider_is_reused_when_requested" {
  variables {
    create_oidc_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "no provider may be created when create_oidc_provider is false"
  }
}

run "budget_is_one_dollar_monthly" {
  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "1" && aws_budgets_budget.monthly.time_unit == "MONTHLY"
    error_message = "budget must be 1 USD per month"
  }
}

run "bad_bucket_suffix_is_rejected" {
  command = plan

  variables {
    state_bucket_suffix = "Bad Suffix!"
  }

  expect_failures = [var.state_bucket_suffix]
}

run "bad_email_is_rejected" {
  command = plan

  variables {
    budget_alert_email = "not-an-email"
  }

  expect_failures = [var.budget_alert_email]
}

# ---------------------------------------------------------------- apply role

run "apply_role_trusts_only_the_prod_environment" {
  assert {
    condition = (
      jsondecode(aws_iam_role.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:sergo3030@61195883/devops-portfolio@1425913518:environment:prod"
    )
    error_message = "apply role must trust only the prod environment of this repository"
  }

  assert {
    condition     = aws_iam_role.apply.permissions_boundary == aws_iam_policy.boundary.arn
    error_message = "apply role must carry the permission boundary"
  }
}

run "apply_role_can_only_touch_prod_state" {
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.apply.policy).Statement :
      !contains(flatten([s.Resource]), "*")
    ])
    error_message = "no apply statement may use Resource *"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.apply.policy).Statement[1].Resource
      == "arn:aws:s3:::portfolio-tfstate-x7k2m9qd4t/prod/*"
    )
    error_message = "the apply role may only read and write the prod state keys"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.apply.policy).Statement :
      alltrue([for a in flatten([s.Action]) : startswith(a, "s3:")])
    ])
    error_message = "the state policy of the apply role must hold S3 state access only"
  }
}

# ---------------------------------------------------------------- public ECR login (D40)

run "plan_and_push_roles_can_log_in_to_public_ecr" {
  assert {
    condition = alltrue([
      for policy in [aws_iam_role_policy.plan.policy, aws_iam_role_policy.ecr_push.policy] :
      contains(flatten([for s in jsondecode(policy).Statement : s.Action]), "ecr-public:GetAuthorizationToken")
      && contains(flatten([for s in jsondecode(policy).Statement : s.Action]), "sts:GetServiceBearerToken")
    ])
    error_message = "the plan and ecr-push roles need both actions to log in to public ECR"
  }

  assert {
    condition = alltrue([
      for policy in [aws_iam_role_policy.plan.policy, aws_iam_role_policy.ecr_push.policy] :
      [
        for s in jsondecode(policy).Statement :
        s.Condition.StringEquals["sts:AWSServiceName"] if s.Action == "sts:GetServiceBearerToken"
      ] == ["ecr-public.amazonaws.com"]
    ])
    error_message = "sts:GetServiceBearerToken must be limited to the ECR Public service"
  }
}

run "no_role_can_push_to_public_ecr_or_use_other_public_ecr_actions" {
  assert {
    condition = alltrue([
      for policy in [aws_iam_role_policy.plan.policy, aws_iam_role_policy.ecr_push.policy, aws_iam_role_policy.apply.policy, aws_iam_role_policy.apply_prod_resources.policy] :
      alltrue([
        for a in flatten([for s in jsondecode(policy).Statement : s.Action]) :
        !startswith(a, "ecr-public:") || a == "ecr-public:GetAuthorizationToken"
      ])
    ])
    error_message = "the only ecr-public action any role may have is GetAuthorizationToken (no pushing to a public registry)"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_policy.boundary.policy).Statement[0].Action, "ecr-public:GetAuthorizationToken")
    error_message = "the boundary must allow the login token, or the roles' permission would be ignored"
  }

  assert {
    condition     = !contains(jsondecode(aws_iam_policy.boundary.policy).Statement[0].Action, "ecr-public:*")
    error_message = "the boundary must not allow all of ECR Public"
  }
}

run "apply_role_resource_permissions_name_only_project_resources" {
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.apply_prod_resources.policy).Statement :
      s.Sid == "FindLogGroups" || alltrue([for r in flatten([s.Resource]) : strcontains(r, "portfolio-")])
    ])
    error_message = "every apply statement must name project resources (the prefix), except log group discovery"
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_role_policy.apply_prod_resources.policy).Statement :
      s.Sid if contains(flatten([s.Resource]), "*")
    ] == ["FindLogGroups"]
    error_message = "only logs:DescribeLogGroups (no resource-level support) may use Resource *"
  }

  assert {
    condition     = local.prod_role_arn == "arn:aws:iam::123456789012:role/portfolio-prod-*"
    error_message = "the apply role may manage roles named portfolio-prod-* only, which excludes plan, apply and ecr-push"
  }
}

run "apply_role_can_only_create_roles_with_the_boundary" {
  assert {
    condition = [
      for s in jsondecode(aws_iam_role_policy.apply_prod_resources.policy).Statement :
      s.Condition.StringEquals["iam:PermissionsBoundary"] if s.Sid == "CreateProdRoleWithBoundary"
    ] == ["arn:aws:iam::123456789012:policy/portfolio-boundary"]
    error_message = "iam:CreateRole must require the project's permission boundary"
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_role_policy.apply_prod_resources.policy).Statement :
      s.Condition.StringEquals["iam:PassedToService"] if s.Sid == "PassProdRoleToLambda"
    ] == ["lambda.amazonaws.com"]
    error_message = "the prod role may only be passed to the Lambda service"
  }
}

run "apply_role_cannot_escalate" {
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.apply_prod_resources.policy).Statement :
      alltrue([
        for a in flatten([s.Action]) :
        !contains(["*", "iam:*", "iam:AttachRolePolicy", "iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary", "iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:CreateUser", "iam:CreateAccessKey"], a)
      ])
    ])
    error_message = "the apply role must not be able to attach managed policies, change boundaries or create users or keys"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.apply_prod_resources.policy).Statement :
      alltrue([for a in flatten([s.Action]) : !startswith(a, "s3:") && !startswith(a, "dynamodb:") && !startswith(a, "budgets:")])
    ])
    error_message = "the resource policy must not reach S3, DynamoDB or Budgets"
  }
}

run "plan_role_can_read_budget_tags" {
  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.plan.policy).Statement[3].Action, "budgets:ListTagsForResource")
    error_message = "the plan role needs budgets:ListTagsForResource to refresh the budget"
  }
}

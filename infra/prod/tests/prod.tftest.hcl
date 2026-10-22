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
  mock_resource "aws_ecr_repository" {
    defaults = {
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/portfolio-api"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/portfolio-api"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/portfolio-prod-lambda"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:portfolio-api"
    }
  }
}

variables {
  image_digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}

run "no_image_means_no_function_and_no_url" {
  command = plan

  variables {
    image_digest = null
  }

  assert {
    condition     = length(aws_lambda_function.api) == 0 && length(aws_lambda_function_url.api) == 0
    error_message = "without an image digest there must be no function and no public URL"
  }

  assert {
    condition     = length(aws_lambda_permission.url) == 0 && length(aws_lambda_permission.invoke) == 0
    error_message = "without a function there must be no public invoke permission"
  }

  assert {
    condition     = aws_ecr_repository.api.name == "portfolio-api"
    error_message = "the repository must exist before any image does"
  }
}

run "function_runs_the_image_by_digest" {
  command = plan

  assert {
    condition     = aws_lambda_function.api[0].package_type == "Image"
    error_message = "the function must run a container image"
  }

  assert {
    condition     = aws_lambda_function.api[0].image_uri == "123456789012.dkr.ecr.us-east-1.amazonaws.com/portfolio-api@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    error_message = "the image must be referenced by digest, never by tag"
  }

  assert {
    condition     = join(",", aws_lambda_function.api[0].architectures) == "x86_64" && aws_lambda_function.api[0].memory_size == 512 && aws_lambda_function.api[0].timeout == 10
    error_message = "default size and timeout are the cost-guard values"
  }

  assert {
    condition     = aws_lambda_function.api[0].reserved_concurrent_executions == null
    error_message = "reserved concurrency is optional and off by default (the account quota is 10)"
  }
}

run "reserved_concurrency_can_be_set" {
  command = plan

  variables {
    reserved_concurrency = 2
  }

  assert {
    condition     = aws_lambda_function.api[0].reserved_concurrent_executions == 2
    error_message = "reserved_concurrency must reach the function"
  }
}

run "function_url_is_public_and_has_both_permissions" {
  command = plan

  assert {
    condition     = aws_lambda_function_url.api[0].authorization_type == "NONE"
    error_message = "the API is public by design"
  }

  assert {
    condition     = aws_lambda_permission.url[0].action == "lambda:InvokeFunctionUrl" && aws_lambda_permission.url[0].function_url_auth_type == "NONE"
    error_message = "a public URL needs the InvokeFunctionUrl statement"
  }

  assert {
    condition     = aws_lambda_permission.invoke[0].action == "lambda:InvokeFunction" && aws_lambda_permission.invoke[0].invoked_via_function_url == true
    error_message = "a public URL needs the InvokeFunction statement, limited to calls through the URL"
  }
}

run "repository_is_immutable_scanned_and_keeps_three_images" {
  command = plan

  assert {
    condition     = aws_ecr_repository.api.image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.api.image_scanning_configuration[0].scan_on_push == true
    error_message = "tags must be immutable and images scanned on push"
  }

  assert {
    condition     = aws_ecr_repository.api.force_delete == false
    error_message = "force_delete is for teardown only and must be off by default"
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.api.policy).rules[0].selection.countNumber == 3
    error_message = "the repository keeps the newest three images"
  }
}

run "force_delete_is_switched_on_by_the_variable" {
  command = plan

  variables {
    force_delete_images = true
  }

  assert {
    condition     = aws_ecr_repository.api.force_delete == true
    error_message = "force_delete_images must reach the repository"
  }
}

run "log_group_is_managed_with_seven_day_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.api.name == "/aws/lambda/portfolio-api" && aws_cloudwatch_log_group.api.retention_in_days == 7
    error_message = "the function's log group must be managed here and expire after 7 days"
  }

  assert {
    condition     = aws_lambda_function.api[0].logging_config[0].log_group == "/aws/lambda/portfolio-api"
    error_message = "the function must log into the managed group"
  }
}

run "lambda_role_has_the_boundary_and_writes_only_its_own_logs" {
  command = plan

  assert {
    condition     = aws_iam_role.lambda.permissions_boundary == "arn:aws:iam::123456789012:policy/portfolio-boundary"
    error_message = "the role must carry the project's permission boundary"
  }

  assert {
    condition     = aws_iam_role.lambda.name == "portfolio-prod-lambda"
    error_message = "the apply role may only create roles named portfolio-prod-*"
  }

  assert {
    condition     = jsondecode(aws_iam_role.lambda.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    error_message = "only the Lambda service may assume the role"
  }

  assert {
    condition = (
      join(",", jsondecode(aws_iam_role_policy.lambda_logs.policy).Statement[0].Action) == "logs:CreateLogStream,logs:PutLogEvents"
      && jsondecode(aws_iam_role_policy.lambda_logs.policy).Statement[0].Resource == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/portfolio-api:*"
    )
    error_message = "the function may only write streams in its own log group"
  }
}

run "bad_digest_is_rejected" {
  command = plan

  variables {
    image_digest = "latest"
  }

  expect_failures = [var.image_digest]
}

run "tag_is_not_a_digest" {
  command = plan

  variables {
    image_digest = "sha256:abc"
  }

  expect_failures = [var.image_digest]
}

run "function_name_must_start_with_the_prefix" {
  command = plan

  variables {
    function_name = "other-api"
  }

  expect_failures = [var.function_name]
}

run "too_few_kept_images_are_rejected" {
  command = plan

  variables {
    images_to_keep = 2
  }

  expect_failures = [var.images_to_keep]
}

run "long_retention_and_big_memory_are_rejected" {
  command = plan

  variables {
    log_retention_days = 365
    memory_size        = 4096
  }

  expect_failures = [var.log_retention_days, var.memory_size]
}

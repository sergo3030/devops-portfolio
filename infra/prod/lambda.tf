# The API: a container image on Lambda, reached through a Function URL (no API Gateway, which
# would bill per request). Nothing here exists until image_digest is set.

resource "aws_lambda_function" "api" {
  #checkov:skip=CKV_AWS_50:X-Ray tracing is not used. The API is one function, and CloudWatch logs are enough.
  #checkov:skip=CKV_AWS_115:Reserved concurrency is optional. An account with the default quota of 10 cannot reserve any. Set reserved_concurrency once the quota is raised (decisions.md).
  #checkov:skip=CKV_AWS_116:A dead letter queue is for asynchronous invocations. This function is only called synchronously through its URL.
  #checkov:skip=CKV_AWS_117:No VPC on purpose. The function needs no private resources, and a VPC would need a NAT gateway for internet access (a recurring cost).
  #checkov:skip=CKV_AWS_272:Code signing does not apply to container images. The image is pinned by digest and scanned on push.
  count = local.deploy ? 1 : 0

  function_name = var.function_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}@${var.image_digest}"
  architectures = ["x86_64"] # the image is built on x86_64 runners
  memory_size   = var.memory_size
  timeout       = var.timeout_seconds

  # null leaves the function unreserved.
  reserved_concurrent_executions = var.reserved_concurrency

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.api.name
  }

  depends_on = [aws_iam_role_policy.lambda_logs]
}

resource "aws_lambda_function_url" "api" {
  #checkov:skip=CKV_AWS_258:Public by design: the API serves published, public content to a static site. Abuse is bounded by the cost guards (decisions.md) and the URL is kept out of the site until the API is hardened (task 16).
  count = local.deploy ? 1 : 0

  function_name      = aws_lambda_function.api[0].function_name
  authorization_type = "NONE"
}

# Since October 2025 a public Function URL (auth NONE) needs BOTH statements in the
# function's resource policy. Without them every request is answered with 403.
resource "aws_lambda_permission" "url" {
  #checkov:skip=CKV_AWS_301:Public by design, see the Function URL above. Limited to calls through the URL (function_url_auth_type NONE).
  count = local.deploy ? 1 : 0

  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api[0].function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "invoke" {
  #checkov:skip=CKV_AWS_301:Public by design, see the Function URL above. Limited to calls made through the URL (invoked_via_function_url).
  count = local.deploy ? 1 : 0

  statement_id             = "AllowPublicInvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.api[0].function_name
  principal                = "*"
  invoked_via_function_url = true
}

# What the function itself may do: write its own logs, nothing else. It has no access to
# any other AWS service, so a bug or a compromised request cannot reach anything.

resource "aws_iam_role" "lambda" {
  # The apply role may only create roles named <prefix>-prod-*, and only with the boundary.
  name                 = "${var.name_prefix}-prod-lambda"
  description          = "Execution role of the ${var.function_name} Lambda function: writes its own log group only."
  permissions_boundary = local.boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_logs" {
  name = "write-own-log-group"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # The group is created by this root, so the function never needs logs:CreateLogGroup.
      Sid      = "WriteOwnLogStreams"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.api.arn}:*"
    }]
  })
}

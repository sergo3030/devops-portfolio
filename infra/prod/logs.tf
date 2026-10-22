# Managed here, with a short retention. Without this, Lambda creates the group on first use
# with "never expire", and it survives `tofu destroy` (a leftover that keeps billing).

resource "aws_cloudwatch_log_group" "api" {
  #checkov:skip=CKV_AWS_158:Logs are encrypted by CloudWatch with its own key. A customer-managed KMS key costs about $1 a month.
  #checkov:skip=CKV_AWS_338:Seven days on purpose. The project's cost rule is no recurring cost beyond cents, and the API logs only requests.
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}

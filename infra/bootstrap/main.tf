data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  bucket_name = "${var.name_prefix}-tfstate-${var.state_bucket_suffix}"
  bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_name}"

  # Immutable OIDC subject format (repositories created after 2026-07-15):
  #   repo:OWNER@OWNER_ID/REPO@REPO_ID:<context>
  # The pull_request context is inferred from the documented pattern and is
  # verified in task 8 with the OIDC debugger.
  github_sub_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"

  oidc_url          = "token.actions.githubusercontent.com"
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  ecr_repository_arn = "arn:${data.aws_partition.current.partition}:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_name}"
}

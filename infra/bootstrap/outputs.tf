output "state_bucket_name" {
  description = "Name of the S3 bucket that holds the state of every root."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.state.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider used by the roles."
  value       = local.oidc_provider_arn
}

output "plan_role_arn" {
  description = "Role for `tofu plan` on pull requests."
  value       = aws_iam_role.plan.arn
}

output "ecr_push_role_arn" {
  description = "Role that pushes images to ECR from the main branch."
  value       = aws_iam_role.ecr_push.arn
}

output "permission_boundary_arn" {
  description = "Boundary attached to every project role."
  value       = aws_iam_policy.boundary.arn
}

output "github_oidc_subject_prefix" {
  description = "Subject claim prefix the trust policies match."
  value       = local.github_sub_prefix
}

output "apply_role_arn" {
  description = "Role for deployments from the protected prod environment."
  value       = aws_iam_role.apply.arn
}

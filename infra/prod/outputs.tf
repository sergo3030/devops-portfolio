output "ecr_repository_url" {
  description = "Repository the build pushes images to."
  value       = aws_ecr_repository.api.repository_url
}

output "log_group_name" {
  description = "Log group of the function (7-day retention)."
  value       = aws_cloudwatch_log_group.api.name
}

output "lambda_role_arn" {
  description = "Execution role of the function."
  value       = aws_iam_role.lambda.arn
}

output "function_url" {
  description = "Public HTTPS address of the API. Null until an image digest is deployed. Keep it out of the site until task 16."
  value       = local.deploy ? aws_lambda_function_url.api[0].function_url : null
}

output "deployed_image_digest" {
  description = "Digest of the image the function runs. Null while no function exists."
  value       = var.image_digest
}

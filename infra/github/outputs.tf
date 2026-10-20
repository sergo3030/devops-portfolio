output "repository_full_name" {
  description = "owner/name of the managed repository."
  value       = github_repository.this.full_name
}

output "repository_id" {
  description = "Numeric repository ID (used in the OIDC subject claim)."
  value       = github_repository.this.repo_id
}

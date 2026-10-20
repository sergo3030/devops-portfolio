# The `prod` environment gates every deploy. Its name is part of the OIDC subject
# claim (`...:environment:prod`) that the AWS `apply` role will trust in task 8.

resource "github_repository_environment" "prod" {
  repository  = github_repository.this.name
  environment = "prod"

  can_admins_bypass = false

  # One maintainer: the reviewer is also the person who triggers the deploy, so
  # self-review must stay allowed. The approval is still an explicit extra step.
  prevent_self_review = false

  reviewers {
    users = [var.reviewer_user_id]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "prod_main" {
  repository     = github_repository.this.name
  environment    = github_repository_environment.prod.environment
  branch_pattern = "main"
}

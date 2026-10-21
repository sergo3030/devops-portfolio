# What workflows may do, and which actions they may use.

resource "github_actions_repository_permissions" "this" {
  repository = github_repository.this.name
  enabled    = true

  # Only GitHub-owned actions and the allowlist below can run, and every
  # reference must be a full commit SHA. A new action needs a reviewed change here.
  allowed_actions      = "selected"
  sha_pinning_required = true

  allowed_actions_config {
    github_owned_allowed = true
    verified_allowed     = false
    patterns_allowed     = var.allowed_action_patterns
  }
}

resource "github_workflow_repository_permissions" "this" {
  repository = github_repository.this.name

  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# Lets workflows build the role ARN without the account ID being written in a file:
#   arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/portfolio-plan
# A variable, not a secret. The credentials action masks the ID in logs.
resource "github_actions_variable" "aws_account_id" {
  repository    = github_repository.this.name
  variable_name = "AWS_ACCOUNT_ID"
  value         = var.aws_account_id
}

# Dependabot opens pull requests for vulnerable dependencies.
resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = true

  depends_on = [github_repository_vulnerability_alerts.this]
}

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
#   arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/portfolio-plan
# The ID is not a credential. It is a secret only because GitHub masks secret
# values everywhere in logs, including the step headers that print expanded
# inputs. A plain Actions variable is printed in clear in a public repository's
# logs, and neither the credentials action nor `::add-mask::` can hide it from the
# step that first uses it.
resource "github_actions_secret" "aws_account_id" {
  repository  = github_repository.this.name
  secret_name = "AWS_ACCOUNT_ID"
  value       = var.aws_account_id
}

# The same value for pull requests that Dependabot opens. Workflows that Dependabot triggers read
# secrets from this store only, never from the Actions secrets above, so without it the role ARN
# is empty and the AWS login fails ("Request ARN is invalid"): the plan jobs fail, and the image
# jobs fall back to an anonymous registry pull that gets a 429 (D51). It was first created by hand
# as an experiment, which showed Dependabot runs can then assume the plan role; applying this
# overwrites that value with the same one.
resource "github_dependabot_secret" "aws_account_id" {
  repository  = github_repository.this.name
  secret_name = "AWS_ACCOUNT_ID"
  value       = var.aws_account_id
}

# Dependabot opens pull requests for vulnerable dependencies.
resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = true

  depends_on = [github_repository_vulnerability_alerts.this]
}

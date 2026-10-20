# The repository itself. It was created by hand to bootstrap the project and was
# imported once with `tofu import github_repository.this devops-portfolio`
# (`tofu test` cannot run configurations that contain import blocks).
# Destroying this root must never delete the repository.

resource "github_repository" "this" {
  #checkov:skip=CKV_GIT_1:The repository is public on purpose: it is a portfolio, and the free security features need a public repository.
  #checkov:skip=CKV_GIT_3:Alerts are enabled by the separate github_repository_vulnerability_alerts resource (the inline argument is deprecated).
  #checkov:skip=CKV2_GIT_1:Branch protection is the ruleset in ruleset.tf. Checkov only recognises github_branch_protection.
  name        = var.repository_name
  description = var.repository_description
  visibility  = var.visibility
  topics      = var.topics

  has_issues   = true # the nightly drift workflow opens issues
  has_wiki     = false
  has_projects = false

  # Rebase and merge only: it keeps the commit history as written.
  allow_rebase_merge = true
  allow_squash_merge = false
  allow_merge_commit = false
  allow_auto_merge   = false

  delete_branch_on_merge = true

  # Free on public repositories. Push protection blocks a push that contains a secret.
  # GitHub rejects these settings in the same update that makes a private
  # repository public, so the go-public flip takes two applies (see the runbook).
  dynamic "security_and_analysis" {
    for_each = var.enable_secret_scanning ? [1] : []

    content {
      secret_scanning {
        status = "enabled"
      }
      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Dependabot alerts.
resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

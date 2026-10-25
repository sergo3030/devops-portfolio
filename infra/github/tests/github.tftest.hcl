# Runs with a mocked GitHub provider: no token, no network.

mock_provider "github" {}

variables {
  aws_account_id = "123456789012" # fake, for the mocked tests only
}

run "aws_actions_are_allowed_and_the_account_id_is_a_masked_secret" {
  command = plan

  assert {
    condition     = contains(github_actions_repository_permissions.this.allowed_actions_config[0].patterns_allowed, "aws-actions/configure-aws-credentials@*")
    error_message = "the AWS credentials action must be on the allowlist"
  }

  assert {
    condition     = github_actions_secret.aws_account_id.secret_name == "AWS_ACCOUNT_ID"
    error_message = "workflows read the account ID from the Actions secret AWS_ACCOUNT_ID, so GitHub masks it in logs"
  }
}

run "bad_account_id_is_rejected" {
  command = plan

  variables {
    aws_account_id = "not-an-account"
  }

  expect_failures = [var.aws_account_id]
}

run "only_rebase_merge_is_allowed" {
  command = plan

  assert {
    condition     = github_repository.this.allow_rebase_merge == true
    error_message = "rebase merge must be allowed"
  }

  assert {
    condition     = github_repository.this.allow_squash_merge == false && github_repository.this.allow_merge_commit == false
    error_message = "squash and merge commits must stay off"
  }

  assert {
    condition     = github_repository.this.delete_branch_on_merge == true
    error_message = "merged branches must be deleted"
  }
}

run "repository_is_public_by_default" {
  command = plan

  assert {
    condition     = github_repository.this.visibility == "public"
    error_message = "visibility must default to public"
  }
}

run "visibility_can_be_set_private" {
  command = plan

  variables {
    visibility = "private"
  }

  assert {
    condition     = github_repository.this.visibility == "private"
    error_message = "the visibility variable must reach the repository"
  }
}

run "security_block_is_skipped_while_flipping_to_public" {
  command = plan

  variables {
    enable_secret_scanning = false
  }

  assert {
    condition     = length(github_repository.this.security_and_analysis) == 0
    error_message = "the security block must be omitted when enable_secret_scanning is false"
  }
}

run "secret_scanning_and_push_protection_are_enabled" {
  command = plan

  assert {
    condition     = github_repository.this.security_and_analysis[0].secret_scanning[0].status == "enabled"
    error_message = "secret scanning must be enabled"
  }

  assert {
    condition     = github_repository.this.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    error_message = "push protection must be enabled"
  }
}

run "bad_visibility_is_rejected" {
  command = plan

  variables {
    visibility = "internal"
  }

  expect_failures = [var.visibility]
}

# ---------------------------------------------------------------- ruleset

run "ruleset_requires_pull_requests_with_rebase_only" {
  command = plan

  assert {
    condition     = github_repository_ruleset.main.enforcement == "active"
    error_message = "the ruleset must be active by default"
  }

  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].allowed_merge_methods == tolist(["rebase"])
    error_message = "only rebase merge may be allowed"
  }

  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].required_approving_review_count == 0
    error_message = "a single maintainer cannot require approvals"
  }

  assert {
    condition = (
      github_repository_ruleset.main.rules[0].deletion == true
      && github_repository_ruleset.main.rules[0].non_fast_forward == true
      && github_repository_ruleset.main.rules[0].required_linear_history == true
    )
    error_message = "main must block deletion and force pushes and keep a linear history"
  }
}

run "ruleset_has_no_bypass_actors" {
  command = plan

  assert {
    condition     = length(github_repository_ruleset.main.bypass_actors) == 0
    error_message = "the ruleset must apply to everyone, including the owner"
  }
}

run "ruleset_requires_every_ci_job" {
  command = plan

  assert {
    condition = toset([for c in github_repository_ruleset.main.rules[0].required_status_checks[0].required_check : c.context]) == toset([
      "workflows (actionlint, zizmor)",
      "python (ruff, pytest)",
      "secrets (gitleaks)",
      "iac (checkov)",
      "opentofu (fmt, validate, test)",
      "analyze (python)",
      "analyze (actions)",
      "analyze (javascript-typescript)",
      "review (new dependencies)",
      "image (hadolint, build, smoke)",
      "web (lint, test, build)",
      "e2e (stack, site)",
    ])
    error_message = "required checks must match the CI job names exactly"
  }

  assert {
    condition     = toset([for t in github_repository_ruleset.main.rules[0].required_code_scanning[0].required_code_scanning_tool : t.tool]) == toset(["CodeQL"])
    error_message = "CodeQL results must be required"
  }
}

run "break_glass_disables_the_ruleset" {
  command = plan

  variables {
    ruleset_enforcement = "disabled"
  }

  assert {
    condition     = github_repository_ruleset.main.enforcement == "disabled"
    error_message = "ruleset_enforcement must reach the ruleset"
  }
}

run "bad_enforcement_is_rejected" {
  command = plan

  variables {
    ruleset_enforcement = "evaluate"
  }

  expect_failures = [var.ruleset_enforcement]
}

# ---------------------------------------------------------------- environment

run "prod_environment_needs_the_owner_and_main_only" {
  command = plan

  assert {
    condition     = contains(github_repository_environment.prod.reviewers[0].users, 61195883)
    error_message = "the owner must be the required reviewer"
  }

  assert {
    condition     = github_repository_environment.prod.can_admins_bypass == false
    error_message = "admins must not bypass the environment"
  }

  assert {
    condition     = github_repository_environment_deployment_policy.prod_main.branch_pattern == "main"
    error_message = "only main may deploy to prod"
  }
}

# ---------------------------------------------------------------- actions

run "actions_require_sha_pins_and_an_allowlist" {
  command = plan

  assert {
    condition     = github_actions_repository_permissions.this.sha_pinning_required == true
    error_message = "SHA pinning must be required"
  }

  assert {
    condition     = github_actions_repository_permissions.this.allowed_actions == "selected"
    error_message = "only selected actions may run"
  }

  assert {
    condition     = github_actions_repository_permissions.this.allowed_actions_config[0].verified_allowed == false
    error_message = "verified creators are not trusted automatically"
  }
}

run "workflow_token_is_read_only" {
  command = plan

  assert {
    condition     = github_workflow_repository_permissions.this.default_workflow_permissions == "read"
    error_message = "the default token must be read-only"
  }

  assert {
    condition     = github_workflow_repository_permissions.this.can_approve_pull_request_reviews == false
    error_message = "workflows must not approve pull requests"
  }
}

run "pages_are_published_by_a_workflow" {
  command = plan

  assert {
    condition     = github_repository_pages.this.build_type == "workflow"
    error_message = "Pages must be built by GitHub Actions"
  }
}

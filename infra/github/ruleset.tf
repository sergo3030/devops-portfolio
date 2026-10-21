# Protection for the default branch, as a ruleset. Pull requests are the only way
# to change `main`, and the same checks that CI shows must pass first.
#
# There are no bypass actors: the rules apply to the owner too. Break-glass if a
# broken required check blocks every merge, from the owner's laptop:
#   tofu apply -var ruleset_enforcement=disabled
# fix the check, then apply again without the variable.

locals {
  # Names are the CI job names. They must not change without changing this list.
  required_checks = [
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
  ]
}

resource "github_repository_ruleset" "main" {
  name        = "protect-main"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = var.ruleset_enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      # One maintainer, so no approval is required. The checks are the gate.
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
      allowed_merge_methods             = ["rebase"]
    }

    required_status_checks {
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = local.required_checks

        content {
          context = required_check.value
        }
      }
    }

    required_code_scanning {
      required_code_scanning_tool {
        tool                      = "CodeQL"
        alerts_threshold          = "errors"
        security_alerts_threshold = "high_or_higher"
      }
    }
  }
}

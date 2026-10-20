# Runs with a mocked GitHub provider: no token, no network.

mock_provider "github" {}

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

run "repository_starts_private" {
  command = plan

  assert {
    condition     = github_repository.this.visibility == "private"
    error_message = "visibility must default to private"
  }
}

run "visibility_can_be_set_public" {
  command = plan

  variables {
    visibility = "public"
  }

  assert {
    condition     = github_repository.this.visibility == "public"
    error_message = "the visibility variable must reach the repository"
  }
}

run "bad_visibility_is_rejected" {
  command = plan

  variables {
    visibility = "internal"
  }

  expect_failures = [var.visibility]
}

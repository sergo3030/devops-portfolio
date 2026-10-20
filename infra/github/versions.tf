terraform {
  required_version = ">= 1.10.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13.0"
    }
  }
}

# Authentication: the GITHUB_TOKEN environment variable, filled at run time from
# `gh auth token`. The token is never stored in GitHub, in the repository or in
# state. This root is planned and applied locally only (see docs/decisions.md).
provider "github" {
  owner = var.github_owner
}

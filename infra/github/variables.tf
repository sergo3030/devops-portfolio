variable "github_owner" {
  description = "GitHub user that owns the repository."
  type        = string
  default     = "sergo3030"
}

variable "repository_name" {
  description = "Name of the repository."
  type        = string
  default     = "devops-portfolio"
}

variable "repository_description" {
  description = "Public description of the repository."
  type        = string
  default     = "Over-engineered DevOps portfolio: OpenTofu, AWS Lambda, GitHub OIDC"
}

variable "visibility" {
  description = "Repository visibility. The repository started private and went public at the go-public gate."
  type        = string
  default     = "public"

  validation {
    condition     = contains(["private", "public"], var.visibility)
    error_message = "visibility must be private or public."
  }
}

variable "enable_secret_scanning" {
  description = "Manage secret scanning and push protection. Needs a public repository: apply with false while flipping a private repository to public, then apply again with the default."
  type        = bool
  default     = true
}

variable "ruleset_enforcement" {
  description = "Enforcement of the main-branch ruleset. `disabled` is the break-glass: use it only to fix a broken required check."
  type        = string
  default     = "active"

  validation {
    condition     = contains(["active", "disabled"], var.ruleset_enforcement)
    error_message = "ruleset_enforcement must be active or disabled."
  }
}

variable "reviewer_user_id" {
  description = "Numeric GitHub ID of the person who approves deployments to the prod environment."
  type        = number
  default     = 61195883
}

variable "allowed_action_patterns" {
  description = "Third-party actions that workflows may use (GitHub-owned actions are always allowed). Add a pattern here before using a new action."
  type        = list(string)
  default = [
    "astral-sh/setup-uv@*",
    "opentofu/setup-opentofu@*",
    "aws-actions/configure-aws-credentials@*",
  ]
}

variable "aws_account_id" {
  description = "AWS account ID, published to workflows as the Actions secret AWS_ACCOUNT_ID so it does not appear in any file or log. Pass it with TF_VAR_aws_account_id (read from `aws sts get-caller-identity`). It is not a credential, but GitHub only masks secrets."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be 12 digits."
  }
}

variable "topics" {
  description = "Repository topics."
  type        = list(string)
  default     = ["devops", "opentofu", "aws-lambda", "github-actions", "portfolio"]
}

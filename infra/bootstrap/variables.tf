variable "region" {
  description = "AWS region for everything in this project."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "portfolio"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-21 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "state_bucket_suffix" {
  description = "Random suffix that makes the state bucket name globally unique, without putting the account ID in the repository."
  type        = string
  default     = "x7k2m9qd4t"

  validation {
    condition     = can(regex("^[a-z0-9]{8,16}$", var.state_bucket_suffix))
    error_message = "state_bucket_suffix must be 8-16 lowercase letters or digits."
  }
}

variable "force_destroy" {
  description = "Let `tofu destroy` delete the state bucket with all object versions. Switch on only when tearing down."
  type        = bool
  default     = false
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one (only one per URL is allowed)."
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string
  default     = "sergo3030"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID. Repositories created after 2026-07-15 put it in the OIDC subject claim."
  type        = string
  default     = "61195883"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be numeric."
  }
}

variable "github_repo" {
  description = "Repository name."
  type        = string
  default     = "devops-portfolio"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID (see the immutable OIDC subject format)."
  type        = string
  default     = "1425913518"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repo_id))
    error_message = "github_repo_id must be numeric."
  }
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository created later by the prod root. The push role is limited to it."
  type        = string
  default     = "portfolio-api"
}

variable "budget_limit_usd" {
  description = "Monthly cost budget in USD."
  type        = number
  default     = 1
}

variable "budget_alert_email" {
  description = "Email for Budget and Cost Anomaly alerts. Pass with TF_VAR_budget_alert_email. Never commit it."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must look like an email address."
  }
}

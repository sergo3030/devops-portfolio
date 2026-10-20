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
  description = "Repository visibility. Starts private and is switched to public at the go-public step."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public"], var.visibility)
    error_message = "visibility must be private or public."
  }
}

variable "topics" {
  description = "Repository topics."
  type        = list(string)
  default     = ["devops", "opentofu", "aws-lambda", "github-actions", "portfolio"]
}

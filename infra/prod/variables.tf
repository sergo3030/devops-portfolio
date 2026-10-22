variable "region" {
  description = "AWS region for everything in this project."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix of the project's shared names. The permission boundary is named <prefix>-boundary, and the Lambda role <prefix>-prod-<function> (the apply role may only create roles with that prefix)."
  type        = string
  default     = "portfolio"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-21 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository. Must match ecr_repository_name of the bootstrap root: the push role is limited to that name."
  type        = string
  default     = "portfolio-api"
}

variable "function_name" {
  description = "Name of the Lambda function. Must start with the name prefix: the apply role is limited to portfolio-* functions."
  type        = string
  default     = "portfolio-api"

  validation {
    condition     = startswith(var.function_name, "${var.name_prefix}-")
    error_message = "function_name must start with the name prefix and a hyphen (for example portfolio-api)."
  }
}

variable "image_digest" {
  description = "Digest of the image to run (sha256:...). While null there is no Lambda function and no Function URL, only the repository and the pieces it needs. Deploys are by digest, never by tag."
  type        = string
  default     = null

  validation {
    condition     = var.image_digest == null || can(regex("^sha256:[0-9a-f]{64}$", var.image_digest))
    error_message = "image_digest must look like sha256:<64 hex characters>."
  }
}

variable "memory_size" {
  description = "Lambda memory in MB. Small on purpose: the API only serves a JSON file."
  type        = number
  default     = 512

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 1024
    error_message = "memory_size must be between 128 and 1024 MB (cost guard)."
  }
}

variable "timeout_seconds" {
  description = "Lambda timeout in seconds. Short on purpose (cost guard)."
  type        = number
  default     = 10

  validation {
    condition     = var.timeout_seconds >= 3 && var.timeout_seconds <= 30
    error_message = "timeout_seconds must be between 3 and 30 (cost guard)."
  }
}

variable "reserved_concurrency" {
  description = "Cap on parallel executions (default 2). Needs an account quota above 12, because AWS keeps 10 unreserved: the default quota of 10 allows no reservation (set null there), and the quota here has been 40 since 2026-10-22. 0 blocks every request, which makes it a kill switch."
  type        = number
  default     = 2

  validation {
    condition     = var.reserved_concurrency == null || (var.reserved_concurrency >= 0 && var.reserved_concurrency <= 10)
    error_message = "reserved_concurrency must be null or between 0 and 10."
  }
}

variable "log_retention_days" {
  description = "Days to keep Lambda logs. Short on purpose (cost guard)."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30], var.log_retention_days)
    error_message = "log_retention_days must be 1, 3, 5, 7, 14 or 30."
  }
}

variable "images_to_keep" {
  description = "How many images the repository keeps. At least 3, so pushing two newer images before a deploy cannot expire the image that is running."
  type        = number
  default     = 3

  validation {
    condition     = var.images_to_keep >= 3 && var.images_to_keep <= 10
    error_message = "images_to_keep must be between 3 and 10."
  }
}

variable "force_delete_images" {
  description = "Let `tofu destroy` delete the repository with its images. Switch on (and apply) only when tearing down."
  type        = bool
  default     = false
}

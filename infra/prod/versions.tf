terraform {
  # use_lockfile (S3 native locking) needs 1.10 or later. Valid for Terraform too.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Every AWS resource carries these tags. `just verify-clean` searches for them.
  default_tags {
    tags = {
      Project   = "portfolio"
      ManagedBy = "opentofu"
      Root      = "prod"
    }
  }
}

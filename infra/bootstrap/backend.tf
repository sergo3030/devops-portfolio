# Remote state in the bucket this root creates. Created in two steps:
#   1. first apply with a local backend (this file absent), which creates the bucket
#   2. add this file, then `tofu init -migrate-state`
# On teardown, migrate back to local BEFORE destroying the bucket (see the runbook).

terraform {
  backend "s3" {
    bucket       = "portfolio-tfstate-x7k2m9qd4t"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 locking, no DynamoDB table
  }
}

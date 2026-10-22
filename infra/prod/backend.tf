# Remote state in the bucket the bootstrap root created. The apply role may only touch the
# prod/ key prefix, so this key must stay under it.

terraform {
  backend "s3" {
    bucket       = "portfolio-tfstate-x7k2m9qd4t"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 locking, no DynamoDB table
  }
}

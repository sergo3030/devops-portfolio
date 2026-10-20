# State lives in the bucket created by the bootstrap root.
terraform {
  backend "s3" {
    bucket       = "portfolio-tfstate-x7k2m9qd4t"
    key          = "github/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

# THROWAWAY test file: deliberately insecure
resource "aws_s3_bucket" "bad" {
  bucket = "portfolio-bad-change-test"
  acl    = "public-read"
}
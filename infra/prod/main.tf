data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # No Lambda function until an image digest is given (the image is pushed after the repository exists).
  deploy = var.image_digest != null

  # Created by the bootstrap root. Built from its name so no lookup call (and no extra permission) is needed.
  boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name_prefix}-boundary"
}

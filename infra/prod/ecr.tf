# The repository the build pushes to and the function pulls from. Lambda can use images
# only from a private repository in its own region.

resource "aws_ecr_repository" "api" {
  #checkov:skip=CKV_AWS_136:AES-256 (the default) is used. A customer-managed KMS key costs about $1 a month, and the image holds no secrets: it is built from this public repository.
  name = var.ecr_repository_name

  # Tags are written once. The function is deployed by digest, so a tag can never silently change what runs.
  image_tag_mutability = "IMMUTABLE"

  # On only while tearing down: without it `tofu destroy` fails when images are left.
  force_delete = var.force_delete_images

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Storage is billed per GB-month, so old images expire. The count is at least 3 (see
# images_to_keep) so the image that is running is never the oldest.
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the newest ${var.images_to_keep} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.images_to_keep
      }
      action = { type = "expire" }
    }]
  })
}

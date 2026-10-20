# Permission boundary: the most any role of this project can ever do, whatever
# its own policies say. It is the cost-risk allowlist in IAM form:
#   - only the services this project uses are allowed
#   - everything outside one region is denied (global services excepted)
#   - expensive service families are denied explicitly, as documentation
# The apply role (task 8) may only create roles that carry this boundary.

locals {
  boundary_allowed_services = [
    "s3:*",
    "ecr:*",
    "lambda:*",
    "logs:*",
    "dynamodb:*",
    "iam:*",
    "sts:*",
    "budgets:*",
    "ce:*",
    "tag:*",
  ]

  # Global services have no region in the request, so the region deny skips them.
  boundary_global_services = [
    "iam:*",
    "sts:*",
    "budgets:*",
    "ce:*",
    "tag:*",
  ]

  boundary_denied_cost_risks = [
    "ec2:*",
    "elasticloadbalancing:*",
    "rds:*",
    "elasticache:*",
    "redshift:*",
    "es:*",
    "kafka:*",
    "eks:*",
    "ecs:*",
    "sagemaker:*",
    "kinesis:*",
    "apigateway:*",
  ]
}

resource "aws_iam_policy" "boundary" {
  #checkov:skip=CKV_AWS_286:A boundary is a ceiling, not a grant. Identity policies stay least-privilege.
  #checkov:skip=CKV_AWS_287:A boundary is a ceiling, not a grant. Identity policies stay least-privilege.
  #checkov:skip=CKV_AWS_288:A boundary is a ceiling, not a grant. Identity policies stay least-privilege.
  #checkov:skip=CKV_AWS_289:A boundary is a ceiling, not a grant. Identity policies stay least-privilege.
  #checkov:skip=CKV_AWS_290:A boundary is a ceiling, not a grant. Identity policies stay least-privilege.
  #checkov:skip=CKV_AWS_355:A boundary is a ceiling, not a grant. Identity policies stay least-privilege.
  #checkov:skip=CKV2_AWS_40:A boundary is a ceiling, not a grant. Identity policies stay least-privilege.
  name        = "${var.name_prefix}-boundary"
  description = "Permission boundary for all ${var.name_prefix} roles."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowOnlyProjectServices"
        Effect   = "Allow"
        Action   = local.boundary_allowed_services
        Resource = "*"
      },
      {
        Sid       = "DenyOtherRegions"
        Effect    = "Deny"
        NotAction = local.boundary_global_services
        Resource  = "*"
        Condition = {
          StringNotEquals = { "aws:RequestedRegion" = [var.region] }
        }
      },
      {
        Sid      = "DenyCostRiskServices"
        Effect   = "Deny"
        Action   = local.boundary_denied_cost_risks
        Resource = "*"
      },
    ]
  })
}

# GitHub Actions signs in with short-lived OIDC tokens. No AWS keys are stored.
# Only one provider per URL can exist in an account. Delete it on teardown only
# if this project created it (create_oidc_provider = true) and nothing else uses it.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://${local.oidc_url}"
}

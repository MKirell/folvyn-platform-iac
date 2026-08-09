locals {
  github_managed = nonsensitive(var.github_token != "")

  repositories = {
    portfolio = "${var.project}-portfolio-mf"
    console   = "${var.project}-console-mf"
    iac       = "${var.project}-platform-iac"
  }

  shared_frontend_variables = {
    S3_BUCKET                  = aws_s3_bucket.spa.id
    CLOUDFRONT_DISTRIBUTION_ID = aws_cloudfront_distribution.app.id
  }

  frontend_variables = local.github_managed ? {
    (local.repositories.portfolio) = merge(local.shared_frontend_variables, {
      S3_SHELL_PREFIX  = local.portfolio_shell_prefix
      S3_BUNDLE_PREFIX = "${local.bundle_prefix}/${local.portfolio_shell_prefix}"
    })
    (local.repositories.console) = merge(local.shared_frontend_variables, {
      S3_SHELL_PREFIX  = local.console_shell_prefix
      S3_BUNDLE_PREFIX = "${local.bundle_prefix}/${local.console_shell_prefix}"
      PREVIEW_PATH     = "/${local.bundle_prefix}/${local.portfolio_shell_prefix}/preview.html"
    })
  } : {}

  frontend_variable_pairs = merge([
    for repo, variables in local.frontend_variables : {
      for name, value in variables :
      "${repo}/${name}" => { repository = repo, name = name, value = value }
    }
  ]...)

  iac_variables = local.github_managed && var.app_image_tag != "" ? {
    APP_IMAGE_TAG = var.app_image_tag
  } : {}
}

resource "github_actions_variable" "frontend" {
  for_each = local.frontend_variable_pairs

  repository    = each.value.repository
  variable_name = each.value.name
  value         = each.value.value
}

resource "github_actions_variable" "iac" {
  for_each = local.iac_variables

  repository    = local.repositories.iac
  variable_name = each.key
  value         = each.value
}

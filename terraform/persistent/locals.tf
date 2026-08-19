locals {
  repositories = {
    api       = "${var.project}-portfolio-ms"
    portfolio = "${var.project}-portfolio-mf"
    console   = "${var.project}-console-mf"
    iac       = "${var.project}-platform-iac"
  }

  github_repositories = values(local.repositories)

  resource_server = local.repositories.api
  admin_scope     = "${local.resource_server}/admin"

  google_linked   = var.google_client_id != "" && var.google_client_secret != ""
  linkedin_linked = var.linkedin_client_id != "" && var.linkedin_client_secret != ""

  environments = {
    for env in var.environments : env => {
      host_label = env == "prod" ? var.project : "${var.project}-${env}"
      app_url    = "https://${env == "prod" ? var.project : "${var.project}-${env}"}.${var.domain_name}"
      db_name    = env == "prod" ? var.mongodb_db_name : "${var.project}_portfolio"
    }
  }

  auth_domain = "https://auth.${var.domain_name}"

  state_bucket = "${var.legacy_name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}"

  callback_urls = {
    for env, cfg in local.environments : env => concat(
      ["${cfg.app_url}/auth/callback"],
      env == "dev" ? ["http://localhost:5174/auth/callback"] : [],
    )
  }

  logout_urls = {
    for env, cfg in local.environments : env => concat(
      [cfg.app_url],
      env == "dev" ? ["http://localhost:5174"] : [],
    )
  }
}

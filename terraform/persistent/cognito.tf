resource "aws_cognito_user_pool" "main" {
  name = var.project

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"
  deletion_protection      = "INACTIVE"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }
}

resource "aws_cognito_resource_server" "api" {
  user_pool_id = aws_cognito_user_pool.main.id
  identifier   = local.resource_server
  name         = "Portfolio data microservice"

  scope {
    scope_name        = "admin"
    scope_description = "Full CRUD over the portfolio data domain"
  }
}

resource "aws_cognito_identity_provider" "google" {
  count = local.google_linked ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id                     = var.google_client_id
    client_secret                 = var.google_client_secret
    authorize_scopes              = "openid profile email"
    attributes_url_add_attributes = "true"
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    given_name     = "given_name"
    family_name    = "family_name"
    picture        = "picture"
    username       = "sub"
  }
}

resource "aws_cognito_identity_provider" "linkedin" {
  count = local.linkedin_linked ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "LinkedIn"
  provider_type = "OIDC"

  provider_details = {
    client_id                 = var.linkedin_client_id
    client_secret             = var.linkedin_client_secret
    oidc_issuer               = "https://www.linkedin.com/oauth"
    authorize_scopes          = "openid profile email"
    attributes_request_method = "GET"
  }

  attribute_mapping = {
    email       = "email"
    name        = "name"
    given_name  = "given_name"
    family_name = "family_name"
    picture     = "picture"
    username    = "sub"
  }
}

resource "aws_cognito_user_pool_client" "app" {
  for_each = local.environments

  name         = "${var.project}-console-${each.key}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "profile", "email"]

  supported_identity_providers = compact([
    "COGNITO",
    local.google_linked ? "Google" : "",
    local.linkedin_linked ? "LinkedIn" : "",
  ])

  callback_urls = local.callback_urls[each.key]
  logout_urls   = local.logout_urls[each.key]

  read_attributes  = ["email", "email_verified", "name", "given_name", "family_name", "picture"]
  write_attributes = ["email", "name", "given_name", "family_name", "picture"]

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]

  access_token_validity  = 15
  id_token_validity      = 15
  refresh_token_validity = 7

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  depends_on = [
    aws_cognito_resource_server.api,
    aws_cognito_identity_provider.google,
    aws_cognito_identity_provider.linkedin,
  ]

  lifecycle {
    ignore_changes = [generate_secret]
  }
}

resource "aws_cognito_user_pool_client" "ci" {
  name         = "${var.project}-ci"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = [local.admin_scope]

  supported_identity_providers = ["COGNITO"]

  access_token_validity = 60

  token_validity_units {
    access_token = "minutes"
  }

  enable_token_revocation = true

  depends_on = [aws_cognito_resource_server.api]

  lifecycle {
    ignore_changes = [generate_secret]
  }
}

resource "aws_cognito_user_group" "platform" {
  name         = "${var.project}-platform"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Operates the platform. Owns no portfolio and is never provisioned one."
  precedence   = 0
}

resource "aws_cognito_user_in_group" "platform_operators" {
  for_each = toset(var.platform_operator_usernames)

  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.platform.name
  username     = each.value
}


locals {
  tags = {
    Project     = var.project
    Environment = var.environment
    Stack       = "main"
    ManagedBy   = "terraform"
  }

  crawlable   = var.environment == "prod"
  owns_domain = var.environment == "prod"
  host_label  = var.environment == "prod" ? var.project : "${var.project}-${var.environment}"
  app_domain  = "${local.host_label}.${var.domain_name}"
  auth_domain = "auth.${var.domain_name}"
  app_url     = "https://${local.app_domain}"

  wildcard_domain = "*.${var.domain_name}"
  cert_domains    = [local.wildcard_domain]

  console_shell_prefix   = "console"
  portfolio_shell_prefix = "portfolio"
  bundle_prefix          = "app"

  console_shell_key   = "${local.console_shell_prefix}/index.html"
  portfolio_shell_key = "${local.portfolio_shell_prefix}/index.html"

  avatar_hosts = [
    "https://lh3.googleusercontent.com",
    "https://media.licdn.com",
  ]

  asset_behaviors = {
    "/imgs/*"  = aws_cloudfront_response_headers_policy.assets_locked.id
    "/files/*" = aws_cloudfront_response_headers_policy.app.id
    "/og/*"    = aws_cloudfront_response_headers_policy.app.id
  }

  root_file_paths = ["robots.txt", "sitemap.xml"]

  crawler_agents = [
    "*",
    "GPTBot",
    "ChatGPT-User",
    "OAI-SearchBot",
    "ClaudeBot",
    "Claude-Web",
    "anthropic-ai",
    "PerplexityBot",
    "Perplexity-User",
    "Google-Extended",
    "Applebot-Extended",
    "Bytespider",
    "CCBot",
  ]

  resource_server = local.persistent.resource_server
  admin_scope     = "${local.resource_server}/admin"

  deploy_app = var.app_image_tag != ""
  use_lambda = var.compute_mode == "lambda"

  integration_id = local.use_lambda ? (
    length(aws_apigatewayv2_integration.lambda) > 0 ? aws_apigatewayv2_integration.lambda[0].id : ""
    ) : (
    length(aws_apigatewayv2_integration.fargate) > 0 ? aws_apigatewayv2_integration.fargate[0].id : ""
  )

  google_linked = var.google_client_id != "" && var.google_client_secret != ""

  callback_urls = [
    "${local.app_url}/auth/callback",
    "http://localhost:5174/auth/callback",
  ]

  logout_urls = [
    local.app_url,
    "http://localhost:5174",
  ]

  cors_origins = join(",", concat(
    [local.app_url],
    var.environment == "prod" ? [] : ["http://localhost:5173", "http://localhost:5174"],
  ))

  app_environment = {
    NODE_ENV                     = "production"
    PORT                         = "3000"
    API_PREFIX                   = "api/v1"
    AWS_LWA_PORT                 = "3000"
    AWS_LWA_READINESS_CHECK_PATH = "/api/v1/health"
    MONGODB_URI                  = local.persistent.mongodb_uri[var.environment]
    MONGODB_DB_NAME              = local.persistent.mongodb_db_name[var.environment]
    CORS_ORIGINS                 = local.cors_origins
    COGNITO_REGION               = var.aws_region
    COGNITO_USER_POOL_ID         = local.persistent.cognito_user_pool_id
    COGNITO_RESOURCE_SERVER      = local.resource_server
    COGNITO_ALLOWED_CLIENT_IDS = join(",", [
      local.persistent.cognito_console_client_ids[var.environment],
      local.persistent.cognito_ci_client_id,
    ])
    COGNITO_FRONTEND_CLIENT_ID = local.persistent.cognito_console_client_ids[var.environment]
    COGNITO_HOSTED_UI_DOMAIN   = var.dns_validated ? "https://${local.auth_domain}" : ""
    LOG_LEVEL                  = "log"
    APP_ENV                    = var.environment
    APP_IMAGE_TAG              = var.app_image_tag
    ACCESS_ALLOWED_EMAILS      = join(",", lookup(var.access_allowed_emails, var.environment, []))
    PRERENDER_FUNCTION_NAME    = local.prerender_live ? local.prerender_name : ""
    PRERENDER_REGION           = var.aws_region
    ASSETS_BUCKET              = aws_s3_bucket.assets.id
    ASSETS_REGION              = var.aws_region
    ASSETS_BASE_URL            = var.dns_validated ? local.app_url : ""
  }
}

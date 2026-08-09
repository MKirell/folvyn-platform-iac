data "aws_caller_identity" "current" {}

output "route53_nameservers" {
  description = "Set these four as the custom nameservers for mkirell.com at Squarespace."
  value       = local.persistent.route53_nameservers
}

output "site_urls" {
  description = "Where everything lives once the nameservers have propagated."
  value = var.dns_validated ? {
    console   = local.app_url
    portfolio = "${local.app_url}/fol/<slug>"
    api       = "${local.app_url}/api/v1"
    login     = "https://${local.auth_domain}"
    } : {
    console   = "https://${aws_cloudfront_distribution.app.domain_name}"
    portfolio = "https://${aws_cloudfront_distribution.app.domain_name}/fol/<slug>"
    api       = aws_apigatewayv2_api.main.api_endpoint
    login     = "pending nameserver delegation"
  }
}

output "cognito_user_pool_id" {
  description = "Feed into the microservice as COGNITO_USER_POOL_ID."
  value       = local.persistent.cognito_user_pool_id
}

output "cognito_console_client_id" {
  description = "Public SPA client. Safe to embed in a frontend build."
  value       = local.persistent.cognito_console_client_ids[var.environment]
}

output "cognito_ci_client_id" {
  description = "Client-credentials client used by CI."
  value       = local.persistent.cognito_ci_client_id
}

output "cognito_ci_client_secret" {
  description = "Secret for the CI client. terraform output -raw cognito_ci_client_secret"
  value       = local.persistent.cognito_ci_client_secret
  sensitive   = true
}

output "ecr_repository_url" {
  description = "Push the microservice image here."
  value       = local.persistent.ecr_repository_url
}

output "api_endpoint" {
  description = "Direct API Gateway URL. CloudFront fronts it at /api."
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "cloudfront_domain" {
  description = "Direct CloudFront URL, before the custom domain is attached."
  value       = aws_cloudfront_distribution.app.domain_name
}

output "cloudfront_distribution_id" {
  description = "Invalidate this after either front end is deployed."
  value       = aws_cloudfront_distribution.app.id
}

output "spa_bucket" {
  description = "Both front ends. console/ and portfolio/ hold the shells, app/ holds the bundles."
  value       = aws_s3_bucket.spa.id
}

output "assets_bucket" {
  description = "Portfolio files, images and flags. Served under /files, /imgs and /flags."
  value       = aws_s3_bucket.assets.id
}

output "mongodb_uri" {
  description = "Connection string with credentials. terraform output -raw mongodb_uri"
  value       = local.persistent.mongodb_uri[var.environment]
  sensitive   = true
}

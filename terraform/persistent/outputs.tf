output "route53_zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "route53_nameservers" {
  value = aws_route53_zone.main.name_servers
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  value = aws_cognito_user_pool.main.arn
}

output "cognito_console_client_ids" {
  description = "Console app client per environment."
  value       = { for env, client in aws_cognito_user_pool_client.app : env => client.id }
}

output "cognito_ci_client_id" {
  value = aws_cognito_user_pool_client.ci.id
}

output "cognito_ci_client_secret" {
  value     = aws_cognito_user_pool_client.ci.client_secret
  sensitive = true
}

output "resource_server" {
  value = local.resource_server
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "mongodb_uri" {
  value     = local.mongodb_srv
  sensitive = true
}

output "mongodb_db_name" {
  value = { for env, cfg in local.environments : env => cfg.db_name }
}

output "github_deploy_role_arns" {
  description = "Deploy role per environment. Terraform sets these as GitHub environment variables already."
  value       = { for env, role in aws_iam_role.github_deploy : env => role.arn }
}

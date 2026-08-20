locals {
  github_managed = nonsensitive(var.github_token != "")

  all_repositories = local.github_managed ? toset(local.github_repositories) : toset([])

  repository_environments = local.github_managed ? {
    for pair in setproduct(local.github_repositories, var.environments) :
    "${pair[0]}/${pair[1]}" => { repository = pair[0], environment = pair[1] }
  } : {}

  environment_variables = {
    for env, cfg in local.environments : env => {
      (local.repositories.api) = {
        AWS_REGION           = var.aws_region
        AWS_DEPLOY_ROLE_ARN  = aws_iam_role.github_deploy[env].arn
        API_BASE_URL         = "${cfg.app_url}/api/v1"
        ECR_REPOSITORY       = aws_ecr_repository.api.name
        LAMBDA_FUNCTION_NAME = "${var.project}-portfolio-ms-${env}"
      }
      (local.repositories.portfolio) = {
        AWS_REGION          = var.aws_region
        AWS_DEPLOY_ROLE_ARN = aws_iam_role.github_deploy[env].arn
        API_BASE_URL        = "${cfg.app_url}/api/v1"
        SITE_URL            = cfg.app_url
      }
      (local.repositories.console) = {
        AWS_REGION          = var.aws_region
        AWS_DEPLOY_ROLE_ARN = aws_iam_role.github_deploy[env].arn
        API_BASE_URL        = "${cfg.app_url}/api/v1"
        SITE_URL            = cfg.app_url
        PORTFOLIO_URL       = cfg.app_url
        COGNITO_DOMAIN      = local.auth_domain
        COGNITO_CLIENT_ID   = aws_cognito_user_pool_client.app[env].id
      }
      (local.repositories.iac) = {
        AWS_REGION          = var.aws_region
        AWS_DEPLOY_ROLE_ARN = aws_iam_role.github_deploy[env].arn
        TF_STATE_BUCKET     = local.state_bucket
      }
    }
  }

  variable_triples = local.github_managed ? merge([
    for env in var.environments : merge([
      for repo in local.github_repositories : {
        for name, value in local.environment_variables[env][repo] :
        "${repo}/${env}/${name}" => {
          repository  = repo
          environment = env
          name        = name
          value       = value
        }
      }
    ]...)
  ]...) : {}

  iac_secret_names = local.github_managed ? toset([
    "MONGODBATLAS_ORG_ID",
    "MONGODBATLAS_PUBLIC_KEY",
    "MONGODBATLAS_PRIVATE_KEY",
    "GOOGLE_CLIENT_ID",
    "GOOGLE_CLIENT_SECRET",
    "LINKEDIN_CLIENT_ID",
    "LINKEDIN_CLIENT_SECRET",
    "GH_TOKEN",
  ]) : toset([])

  iac_secret_values = {
    MONGODBATLAS_ORG_ID      = var.mongodbatlas_org_id
    MONGODBATLAS_PUBLIC_KEY  = var.mongodbatlas_public_key
    MONGODBATLAS_PRIVATE_KEY = var.mongodbatlas_private_key
    GOOGLE_CLIENT_ID         = var.google_client_id
    GOOGLE_CLIENT_SECRET     = var.google_client_secret
    LINKEDIN_CLIENT_ID       = var.linkedin_client_id
    LINKEDIN_CLIENT_SECRET   = var.linkedin_client_secret
    GH_TOKEN                 = var.github_token
  }
}

resource "github_repository_environment" "managed" {
  for_each = local.repository_environments

  repository  = each.value.repository
  environment = each.value.environment

  can_admins_bypass = false

  dynamic "reviewers" {
    for_each = each.value.environment == "prod" ? [1] : []

    content {
      users = var.github_prod_reviewer_ids
    }
  }

  dynamic "deployment_branch_policy" {
    for_each = [1]

    content {
      protected_branches     = false
      custom_branch_policies = true
    }
  }
}

resource "github_repository_environment_deployment_policy" "managed" {
  for_each = local.repository_environments

  repository  = each.value.repository
  environment = github_repository_environment.managed[each.key].environment

  branch_pattern = (
    each.value.repository == local.repositories.iac || each.value.environment == "prod"
    ? "main"
    : "develop"
  )
}

resource "github_actions_environment_variable" "managed" {
  for_each = local.variable_triples

  repository    = each.value.repository
  environment   = github_repository_environment.managed["${each.value.repository}/${each.value.environment}"].environment
  variable_name = each.value.name
  value         = each.value.value
}

resource "github_actions_secret" "iac" {
  for_each = local.iac_secret_names

  repository      = local.repositories.iac
  secret_name     = each.key
  plaintext_value = local.iac_secret_values[each.key]
}

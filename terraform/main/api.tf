resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-api-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = split(",", local.cors_origins)
    allow_methods = ["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 600
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.project}-api-${var.environment}"
  retention_in_days = var.app_log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId  = "$context.requestId"
      httpMethod = "$context.httpMethod"
      path       = "$context.path"
      status     = "$context.status"
      latency    = "$context.responseLatency"
      error      = "$context.error.message"
    })
  }

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito"

  jwt_configuration {
    issuer = "https://cognito-idp.${var.aws_region}.amazonaws.com/${local.persistent.cognito_user_pool_id}"
    audience = [
      local.persistent.cognito_console_client_ids[var.environment],
      local.persistent.cognito_ci_client_id,
    ]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  count = local.use_lambda && local.deploy_app ? 1 : 0

  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api[0].invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_integration" "fargate" {
  count = local.use_fargate ? 1 : 0

  api_id               = aws_apigatewayv2_api.main.id
  integration_type     = "HTTP_PROXY"
  integration_uri      = aws_lb_listener.api[0].arn
  integration_method   = "ANY"
  connection_type      = "VPC_LINK"
  connection_id        = aws_apigatewayv2_vpc_link.fargate[0].id
  timeout_milliseconds = 30000
}

resource "aws_apigatewayv2_route" "public" {
  count = local.deploy_app ? 1 : 0

  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${local.integration_id}"
}

resource "aws_apigatewayv2_route" "admin" {
  for_each = local.deploy_app ? toset([
    "ANY /api/v1/admin/{proxy+}",
    "GET /api/v1/auth/me",
  ]) : toset([])

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.value
  target             = "integrations/${local.integration_id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}


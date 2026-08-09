resource "aws_iam_role" "lambda" {
  count = local.use_lambda && local.deploy_app ? 1 : 0

  name = "${var.project}-portfolio-ms-${var.environment}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  count = local.use_lambda && local.deploy_app ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda" {
  count = local.use_lambda && local.deploy_app ? 1 : 0

  name              = "/aws/lambda/${var.project}-portfolio-ms-${var.environment}"
  retention_in_days = var.app_log_retention_days
}

data "aws_ecr_image" "api" {
  count = local.use_lambda && local.deploy_app ? 1 : 0

  repository_name = element(split("/", local.persistent.ecr_repository_url), 1)
  image_tag       = var.app_image_tag
}

resource "aws_lambda_function" "api" {
  count = local.use_lambda && local.deploy_app ? 1 : 0

  function_name = "${var.project}-portfolio-ms-${var.environment}"
  role          = aws_iam_role.lambda[0].arn
  package_type  = "Image"
  image_uri     = "${local.persistent.ecr_repository_url}@${data.aws_ecr_image.api[0].image_digest}"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  environment {
    variables = local.app_environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda,
  ]
}

resource "aws_lambda_permission" "api_gateway" {
  count = local.use_lambda && local.deploy_app ? 1 : 0

  statement_id  = "AllowInvokeFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

data "aws_iam_policy_document" "lambda_assets" {
  statement {
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.assets.arn]
  }
}

resource "aws_iam_role_policy" "lambda_assets" {
  count = local.use_lambda ? 1 : 0

  name   = "${var.project}-lambda-assets-${var.environment}"
  role   = aws_iam_role.lambda[0].id
  policy = data.aws_iam_policy_document.lambda_assets.json
}

data "aws_iam_policy_document" "lambda_directory" {
  statement {
    actions = [
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminDeleteUser",
      "cognito-idp:ListUsers",
    ]
    resources = ["arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/${local.persistent.cognito_user_pool_id}"]
  }
}

resource "aws_iam_role_policy" "lambda_directory" {
  count = local.use_lambda ? 1 : 0

  name   = "${var.project}-lambda-directory-${var.environment}"
  role   = aws_iam_role.lambda[0].id
  policy = data.aws_iam_policy_document.lambda_directory.json
}

locals {
  prerender_name = "${var.project}-prerender-${var.environment}"
  prerender_live = var.prerender_enabled && local.deploy_app
}

data "archive_file" "prerender_placeholder" {
  count = local.prerender_live ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/.terraform/prerender-placeholder.zip"

  source {
    filename = "index.js"
    content  = "exports.handler = async () => { throw new Error('the renderer has not been deployed yet') }"
  }
}

resource "aws_iam_role" "prerender" {
  count = local.prerender_live ? 1 : 0

  name = "${local.prerender_name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prerender_logs" {
  count = local.prerender_live ? 1 : 0

  role       = aws_iam_role.prerender[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "prerender" {
  statement {
    sid       = "ReadTheShell"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.spa.arn}/${local.console_shell_prefix}/*", "${aws_s3_bucket.spa.arn}/${local.portfolio_shell_prefix}/*"]
  }

  statement {
    sid     = "WriteThePrerenderedPages"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.spa.arn}/${local.portfolio_shell_prefix}/${var.portfolio_prefix}/*",
      "${aws_s3_bucket.spa.arn}/sitemap.xml",
    ]
  }

  statement {
    sid       = "WriteTheCards"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.assets.arn}/og/*"]
  }

  statement {
    sid       = "InvalidateWhatItWrote"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.app.arn]
  }
}

resource "aws_iam_role_policy" "prerender" {
  count = local.prerender_live ? 1 : 0

  name   = local.prerender_name
  role   = aws_iam_role.prerender[0].id
  policy = data.aws_iam_policy_document.prerender.json
}

resource "aws_cloudwatch_log_group" "prerender" {
  count = local.prerender_live ? 1 : 0

  name              = "/aws/lambda/${local.prerender_name}"
  retention_in_days = var.app_log_retention_days
}

resource "aws_lambda_function" "prerender" {
  count = local.prerender_live ? 1 : 0

  function_name = local.prerender_name
  role          = aws_iam_role.prerender[0].arn
  runtime       = "nodejs22.x"
  handler       = "index.handler"

  filename         = data.archive_file.prerender_placeholder[0].output_path
  source_code_hash = data.archive_file.prerender_placeholder[0].output_base64sha256

  memory_size = var.prerender_memory_mb
  timeout     = var.prerender_timeout_seconds

  environment {
    variables = {
      API_BASE_URL               = "${local.app_url}/api/v1"
      SITE_URL                   = local.app_url
      ASSETS_BASE_URL            = local.app_url
      SPA_BUCKET                 = aws_s3_bucket.spa.id
      ASSETS_BUCKET              = aws_s3_bucket.assets.id
      SHELL_PREFIX               = local.portfolio_shell_prefix
      PORTFOLIO_PREFIX           = var.portfolio_prefix
      CLOUDFRONT_DISTRIBUTION_ID = aws_cloudfront_distribution.app.id
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [
    aws_iam_role_policy_attachment.prerender_logs,
    aws_cloudwatch_log_group.prerender,
  ]
}

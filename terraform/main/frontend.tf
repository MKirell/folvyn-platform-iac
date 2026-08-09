moved {
  from = aws_cloudfront_distribution.portfolio
  to   = aws_cloudfront_distribution.app
}

resource "aws_s3_bucket" "spa" {
  bucket        = "${var.project}-spa-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket = aws_s3_bucket.spa.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "${var.project}-spa-${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "router" {
  name    = "${var.project}-router-${var.environment}"
  runtime = "cloudfront-js-2.0"
  comment = "Sends /${var.portfolio_prefix}/* to the portfolio shell and everything else to the console."
  publish = true

  code = templatefile("${path.module}/functions/router.js.tftpl", {
    portfolio_prefix = var.portfolio_prefix
    portfolio_shell  = local.portfolio_shell_key
    console_shell    = local.console_shell_key
  })
}

resource "aws_s3_object" "robots" {
  bucket        = aws_s3_bucket.spa.id
  key           = "robots.txt"
  content_type  = "text/plain; charset=utf-8"
  cache_control = "public,max-age=3600"

  content = templatefile("${path.module}/templates/robots.txt.tftpl", {
    crawlable        = local.crawlable
    agents           = local.crawler_agents
    portfolio_prefix = var.portfolio_prefix
    site_url         = local.app_url
  })
}

resource "aws_cloudfront_response_headers_policy" "app" {
  name    = "${var.project}-security-headers-${var.environment}"
  comment = "One origin now serves the console and every portfolio."

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    content_security_policy {
      override = true
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline'",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src 'self' https://fonts.gstatic.com",
        "img-src 'self' data: blob:",
        "connect-src 'self' https://${local.auth_domain} https://${aws_s3_bucket.assets.bucket_regional_domain_name}",
        "frame-src 'self'",
        "frame-ancestors 'self'",
        "base-uri 'none'",
        "form-action 'none'",
        "object-src 'none'",
      ])
    }
  }

  dynamic "custom_headers_config" {
    for_each = local.crawlable ? [] : [1]

    content {
      items {
        header   = "X-Robots-Tag"
        value    = "noindex, nofollow, noarchive"
        override = true
      }
    }
  }
}

resource "aws_cloudfront_distribution" "app" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  comment         = "${var.project} platform (${var.environment})"

  aliases = var.dns_validated ? [local.app_domain] : []

  origin {
    domain_name              = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id                = "spa-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  origin {
    domain_name              = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id                = "assets-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  origin {
    domain_name = replace(aws_apigatewayv2_api.main.api_endpoint, "https://", "")
    origin_id   = "api-gateway"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "spa-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.app.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.router.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "api-gateway"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  ordered_cache_behavior {
    path_pattern           = "/collect"
    target_origin_id       = "api-gateway"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.collect.id
  }

  ordered_cache_behavior {
    path_pattern           = "/${local.bundle_prefix}/*"
    target_origin_id       = "spa-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.app.id
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.asset_behaviors

    content {
      path_pattern           = ordered_cache_behavior.key
      target_origin_id       = "assets-s3"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
      response_headers_policy_id = ordered_cache_behavior.value
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = toset(local.root_file_paths)

    content {
      path_pattern           = "/${ordered_cache_behavior.value}"
      target_origin_id       = "spa-s3"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.app.id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.dns_validated ? [1] : []
    content {
      acm_certificate_arn      = aws_acm_certificate.edge.arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.dns_validated ? [] : [1]
    content {
      cloudfront_default_certificate = true
    }
  }

  depends_on = [aws_acm_certificate_validation.edge]
}

data "aws_iam_policy_document" "spa_bucket" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.spa.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.app.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  policy = data.aws_iam_policy_document.spa_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.spa]
}

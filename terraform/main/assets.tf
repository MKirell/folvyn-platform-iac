resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project}-assets-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = [
      local.app_url,
      "http://localhost:5174",
    ]
    allowed_headers = ["content-type"]
    max_age_seconds = 600
  }
}

resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "${var.project}-assets-${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "assets_bucket" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.app.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.assets]
}

resource "aws_cloudfront_response_headers_policy" "assets_locked" {
  name    = "${var.project}-assets-locked-${var.environment}"
  comment = "An uploaded SVG must never run script in the portfolio's own origin."

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'none'; style-src 'unsafe-inline'; sandbox"
      override                = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
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

resource "aws_cloudfront_origin_request_policy" "collect" {
  name    = "${var.project}-collect-${var.environment}"
  comment = "Forwards viewer country so geography arrives without an IP ever being handled."

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = [
        "CloudFront-Viewer-Country",
        "Accept-Language",
        "Content-Type",
        "Origin",
        "Referer",
        "User-Agent",
      ]
    }
  }

  cookies_config {
    cookie_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}

locals {
  validation_options = {
    for o in aws_acm_certificate.edge.domain_validation_options : o.domain_name => o
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = toset(local.cert_domains)

  zone_id         = local.persistent.route53_zone_id
  name            = local.validation_options[each.key].resource_record_name
  type            = local.validation_options[each.key].resource_record_type
  records         = [local.validation_options[each.key].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_route53_record" "apex" {
  count = local.owns_domain ? 1 : 0

  zone_id = local.persistent.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "app" {
  zone_id = local.persistent.route53_zone_id
  name    = local.app_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "app_ipv6" {
  zone_id = local.persistent.route53_zone_id
  name    = local.app_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "auth" {
  count = local.owns_domain && var.dns_validated ? 1 : 0

  zone_id = local.persistent.route53_zone_id
  name    = local.auth_domain
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.main[0].cloudfront_distribution
    zone_id                = aws_cognito_user_pool_domain.main[0].cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}

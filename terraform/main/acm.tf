resource "aws_acm_certificate" "edge" {
  provider = aws.us_east_1

  domain_name       = local.wildcard_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "edge" {
  count    = var.dns_validated ? 1 : 0
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.edge.arn

  validation_record_fqdns = [
    for o in aws_acm_certificate.edge.domain_validation_options :
    aws_route53_record.cert_validation[o.domain_name].fqdn
  ]

  timeouts {
    create = "45m"
  }
}

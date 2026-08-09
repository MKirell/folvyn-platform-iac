resource "aws_cognito_user_pool_domain" "main" {
  count = var.dns_validated ? 1 : 0

  domain          = local.auth_domain
  user_pool_id    = local.persistent.cognito_user_pool_id
  certificate_arn = aws_acm_certificate.edge.arn

  depends_on = [
    aws_acm_certificate_validation.edge,
    aws_route53_record.apex,
  ]
}

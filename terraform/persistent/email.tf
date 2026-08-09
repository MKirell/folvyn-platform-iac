locals {
  dkim_chunks = [
    for offset in range(0, length(var.mail_dkim_record), 255) :
    substr(var.mail_dkim_record, offset, 255)
  ]

  dkim_value = join("\" \"", local.dkim_chunks)
}

resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 3600
  records = var.mail_mx_records
}

resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 3600
  records = concat([var.mail_spf_record], var.mail_domain_verifications)
}

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 3600
  records = [var.mail_dmarc_record]
}

resource "aws_route53_record" "dkim" {
  count = var.mail_dkim_record == "" ? 0 : 1

  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.mail_dkim_selector}._domainkey.${var.domain_name}"
  type    = "TXT"
  ttl     = 3600
  records = [local.dkim_value]
}

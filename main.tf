
locals {
  prod_stages    = ["prod", "production", "main"]
  tld            = element(local.domain_parts, length(local.domain_parts) - 1)
  vpc_ids        = concat(var.zone_vpcs, data.terraform_remote_state.vpc.*.outputs.vpc_id)
  domain_parts   = var.parent_domain_name == "" ? [var.tld] : split(".", var.parent_domain_name)
  fqdn           = var.domain_name == "" ? format("%s.%s", module.label.id, local.tld) : var.domain_name
  label_order    = contains(local.prod_stages, var.stage) && var.omit_prod_stage ? ["name", "attributes", "namespace"] : ["name", "stage", "attributes", "namespace"]
  tag_overwrites = { 
    Name = format("ACM %s", var.name == "" ? local.fqdn : var.name) 
  }

  subject_alternative_names      = distinct(concat([format("*.%s", local.fqdn)], var.certificate_alternative_names))
  domain_validation_options_list = var.certificate_enabled ? aws_acm_certificate.default[0].domain_validation_options : []
}

data "terraform_remote_state" "vpc" {
  count   = var.vpc_module_state == "" ? 0 : 1
  backend = "s3"

  config = {
    bucket = var.tf_bucket
    key    = var.vpc_module_state
  }
}

module "label" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.15.0"
  namespace   = var.namespace
  stage       = var.stage
  attributes  = var.attributes
  name        = var.name
  label_order = local.label_order
  tags        = merge(var.tags, local.tag_overwrites)
  delimiter   = "."
}

resource "aws_route53_zone" "dns_zone" {
  provider = aws.member_account
  name     = local.fqdn
  tags     = module.label.tags

  dynamic "vpc" {
    iterator = zone
    for_each = local.vpc_ids

    content {
      vpc_id = zone.value
    }
  }
}

data "aws_route53_zone" "parent" {
  provider     = aws.parent_account
  count        = var.parent_domain_name == "" ? 0 : 1
  name         = format("%s.", var.parent_domain_name)
  private_zone = var.is_parent_private_zone
}

resource "aws_route53_record" "ns" {
  provider        = aws.parent_account
  count           = var.parent_domain_name == "" ? 0 : 1
  zone_id         = element(data.aws_route53_zone.parent.*.zone_id, 0)
  name            = local.fqdn
  allow_overwrite = true
  type            = "NS"
  ttl             = 300

  records = [
    aws_route53_zone.dns_zone.name_servers.0,
    aws_route53_zone.dns_zone.name_servers.1,
    aws_route53_zone.dns_zone.name_servers.2,
    aws_route53_zone.dns_zone.name_servers.3,
  ]
}

resource "aws_acm_certificate" "default" {
  count                     = var.certificate_enabled ? 1 : 0
  provider                  = aws.member_account
  depends_on                = [aws_route53_zone.dns_zone]
  tags                      = module.label.tags
  domain_name               = local.fqdn
  subject_alternative_names = local.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  count           = var.certificate_enabled ? 1 : 0
  provider        = aws.member_account
  zone_id         = aws_route53_zone.dns_zone.zone_id
  name            = lookup(local.domain_validation_options_list[count.index], "resource_record_name")
  type            = lookup(local.domain_validation_options_list[count.index], "resource_record_type")
  records         = [lookup(local.domain_validation_options_list[count.index], "resource_record_value")]
  allow_overwrite = true
  ttl             = 300
}

resource "aws_acm_certificate_validation" "default" {
  count                   = var.certificate_enabled ? 1 : 0
  provider                = aws.member_account
  depends_on              = [aws_route53_record.validation]
  certificate_arn         = join("", aws_acm_certificate.default.*.arn)
  validation_record_fqdns = aws_route53_record.validation.*.fqdn
}

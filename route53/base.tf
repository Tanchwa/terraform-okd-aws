terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {

  // Because of the issue https://github.com/hashicorp/terraform/issues/12570, the consumers cannot count 0/1
  // based on if api_external_lb_dns_name for example, which will be null when there is no external lb for API.
  // So publish_strategy serves an coordinated proxy for that decision.
  public_endpoints = var.publish_strategy == "External" ? true : false

  // GovCloud does not support alias records to NLBs, so use CNAMEs there.
  use_cname = contains(["us-gov-west-1", "us-gov-east-1"], var.region)
  use_alias = !local.use_cname

  // The *.apps wildcard is only created once the ingress load balancer exists
  // (a second apply after the cluster is up). Prefer an explicit hostname when
  // provided; otherwise discover the router-default NLB by tag.
  apps_enabled  = var.manage_ingress_dns
  apps_lookup   = var.manage_ingress_dns && var.ingress_router_lb_hostname == ""
  apps_hostname = var.ingress_router_lb_hostname != "" ? var.ingress_router_lb_hostname : (local.apps_lookup ? data.aws_lb.ingress[0].dns_name : "")
}

# ─── Public DNS in the delegated Route53 zone ─────────────────────────────────
# var.public_zone_id is the public hosted zone for var.base_domain, created at
# the root and delegated from Cloudflare via NS records. CNAMEs (not aliases)
# keep this simple and provider-agnostic and mirror the previous behaviour; the
# targets are LB DNS names, and cluster_domain is a subdomain (never the apex),
# so CNAMEs are valid here.

# api.<cluster_domain> -> external API NLB.
resource "aws_route53_record" "api_external" {
  count = local.public_endpoints ? 1 : 0

  zone_id = var.public_zone_id
  name    = "api.${var.cluster_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [var.api_external_lb_dns_name]
}

# Discover the ingress router-default load balancer by the tags the cloud
# provider stamps on the Service's NLB. Filtered by cluster id so it matches
# exactly one LB. Only a Network LB is discoverable here; for a Classic ELB pass
# ingress_router_lb_hostname instead.
data "aws_lb" "ingress" {
  count = local.apps_lookup ? 1 : 0

  tags = {
    "kubernetes.io/service-name"              = "openshift-ingress/router-default"
    "kubernetes.io/cluster/${var.cluster_id}" = "owned"
  }
}

# *.apps.<cluster_domain> -> ingress LB. Wildcard so every app route
# (<app>.apps.<cluster_domain>) resolves to ingress and the router sorts by Host.
resource "aws_route53_record" "apps" {
  count = local.apps_enabled ? 1 : 0

  zone_id = var.public_zone_id
  name    = "*.apps.${var.cluster_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [local.apps_hostname]
}

# ─── Private (split-horizon) DNS in AWS Route53 ───────────────────────────────
# A private hosted zone attached to the VPC so in-cluster nodes resolve api-int
# (and api) to the internal NLB. This stays in Route53 because Cloudflare cannot
# serve VPC-private records.
resource "aws_route53_zone" "int" {
  name          = var.cluster_domain
  force_destroy = true

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(
    {
      "Name" = "${var.cluster_id}-int"
    },
    var.tags,
  )
}

resource "aws_route53_record" "api_internal_alias" {
  count = local.use_alias ? 1 : 0

  zone_id = aws_route53_zone.int.zone_id
  name    = "api-int.${var.cluster_domain}"
  type    = "A"

  alias {
    name                   = var.api_internal_lb_dns_name
    zone_id                = var.api_internal_lb_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_external_internal_zone_alias" {
  count = local.use_alias ? 1 : 0

  zone_id = aws_route53_zone.int.zone_id
  name    = "api.${var.cluster_domain}"
  type    = "A"

  alias {
    name                   = var.api_internal_lb_dns_name
    zone_id                = var.api_internal_lb_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_internal_cname" {
  count = local.use_cname ? 1 : 0

  zone_id = aws_route53_zone.int.zone_id
  name    = "api-int.${var.cluster_domain}"
  type    = "CNAME"
  ttl     = 10

  records = [var.api_internal_lb_dns_name]
}

resource "aws_route53_record" "api_external_internal_zone_cname" {
  count = local.use_cname ? 1 : 0

  zone_id = aws_route53_zone.int.zone_id
  name    = "api.${var.cluster_domain}"
  type    = "CNAME"
  ttl     = 10

  records = [var.api_internal_lb_dns_name]
}

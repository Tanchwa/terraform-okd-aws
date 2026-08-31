# ─── Public DNS: subdomain delegated from Cloudflare to Route53 ────────────────
# The base domain (andrewsutliff.com) lives in Cloudflare, but the AWS installer
# requires the cluster's public zone to live in Route53: `openshift-install
# create manifests` looks up a public Route53 hosted zone for var.base_domain
# while generating the "DNS Config" asset and fails if one does not exist.
#
# So we host a dedicated subdomain (e.g. okd.andrewsutliff.com) as a public
# Route53 zone and delegate it from the Cloudflare parent zone via NS records.
# This is the standard, fully-supported, upgradeable path (unlike the
# userProvisionedDNS/TechPreviewNoUpgrade alternative).
#
# This zone is created at the ROOT (not inside module.dns) for two reasons:
#   1. module.dns depends on module.installer.infraID, so anything created there
#      would come *after* `create manifests` — too late for the zone lookup.
#   2. module.installer must depend on this zone so it exists first (see main.tf).
# It is tagged from var.aws_extra_tags only (not local.tags), because local.tags
# references module.installer.infraID and would form a dependency cycle.

resource "aws_route53_zone" "public" {
  name = var.base_domain

  tags = merge(
    { "Name" = var.base_domain },
    var.aws_extra_tags,
  )
}

# Look up the Cloudflare-managed parent zone (andrewsutliff.com) so we can
# publish the delegation NS records into it.
data "cloudflare_zones" "parent" {
  count = var.cloudflare_parent_domain == "" ? 0 : 1
  name  = var.cloudflare_parent_domain
}

# Delegate the subdomain to Route53 by publishing the Route53 zone's nameservers
# as NS records in the Cloudflare parent zone. Recreated automatically if the
# Route53 zone is destroyed/recreated (nameservers change on recreate). Low TTL
# keeps re-delegation fast across cluster rebuilds.
#
# count is a fixed 4 (not length(name_servers)): a Route53 public hosted zone
# always gets exactly 4 delegation-set nameservers, and count must be known at
# plan time — name_servers isn't known until the zone is created.
resource "cloudflare_dns_record" "delegation" {
  count = var.cloudflare_parent_domain == "" ? 0 : 4

  zone_id = data.cloudflare_zones.parent[0].result[0].id
  name    = var.base_domain
  type    = "NS"
  content = aws_route53_zone.public.name_servers[count.index]
  ttl     = 300
  proxied = false
}

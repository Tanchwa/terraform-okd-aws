output "cloudflare_zone_id" {
  value = local.cloudflare_zone_id
}

output "private_zone_id" {
  value = aws_route53_zone.int.zone_id
}

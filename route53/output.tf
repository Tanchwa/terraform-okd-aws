output "public_zone_id" {
  value = var.public_zone_id
}

output "private_zone_id" {
  value = aws_route53_zone.int.zone_id
}

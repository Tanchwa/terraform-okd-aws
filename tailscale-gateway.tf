module "tailscale_gateway" {
  source = "../terraform-aws-tailscale-gateway"

  network = {
    vpc_id                   = module.vpc.vpc_id
    tailscale_subnet_id      = module.vpc.private_subnet_ids[0]
    dns_resolver_subnet_id_1 = module.vpc.private_subnet_ids[0]
    dns_resolver_subnet_id_2 = module.vpc.private_subnet_ids[1]
  }

  # Advertise all private subnets so both the internal k8s API LB and all node
  # IPs are reachable over Tailscale.
  subnets_to_advertise = toset(module.vpc.vpc_cidrs)

  tailscale_auth_key = var.tailscale_auth_key
}

output "tailscale_gateway_info" {
  description = "Post-deploy DNS forwarding instructions for the Tailscale gateway."
  value       = module.tailscale_gateway.additional_info
}

terraform {
  required_version = ">= 0.13"

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

variable "machine_cidr" {
  type = string

  description = <<EOF
The IP address space from which to assign machine IPs.
Default "10.0.0.0/16"
EOF
  default = "10.0.0.0/16"
}




variable "base_domain" {
  type = string

  description = <<EOF
The base DNS domain of the cluster. It must NOT contain a trailing period. Some
DNS providers will automatically add this if necessary.

Example: `openshift.example.com`.

Note: This field MUST be set manually prior to creating the cluster.
This applies only to cloud platforms.
EOF

}

variable "cluster_name" {
  type = string

  description = <<EOF
The name of the cluster. It will be suffixed by the base_domain to make cluster_domain.
EOF
}

variable "openshift_pull_secret" {
  type = string
  description = "File containing the pull secret. OKD does not require a Red Hat entitlement; the bundled ./fake_pull_secret.json works. A real Red Hat pull secret (https://console.redhat.com/openshift/install/pull-secret) may still be supplied to pull entitled content."
  default = "./fake_pull_secret.json"
}

variable "use_ipv4" {
  type    = bool
  default = true
  description = "not implemented"
}

variable "use_ipv6" {
  type    = bool
  default = false
  description = "not implemented"
}

variable "openshift_version" {
  type    = string
  description = "OKD release tag. Find valid tags at https://github.com/okd-project/okd/releases"
  default = "4.22.0-okd-scos.8"
}

variable "airgapped" {
  type = map(string)
  default = {
    enabled  = false
    repository = ""
  }
}

variable "proxy_config" {
  type = map(string)
  description = "Not implemented"
  default = {
    enabled    = false
    httpProxy  = "http://user:password@ip:port"
    httpsProxy = "http://user:password@ip:port"
    noProxy    = "ip1,ip2,ip3,.example.com,cidr/mask"
  }
}

variable "openshift_additional_trust_bundle" {
  description = "path to a file with all your additional ca certificates"
  type        = string
  default     = ""
}

variable "openshift_ssh_key" {
  description = "Path to SSH Public Key file to use for OpenShift Installation"
  type        = string
  default     = ""
}

variable "openshift_byo_dns" {
  description = "Tell OKD that DNS is managed outside the cluster (BYO DNS). Must stay true when using the Cloudflare integration so the cluster ingress/DNS operators do not attempt to manage records themselves."
  type        = bool
  default     = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token used by the cloudflare provider to manage the NS delegation records in the parent zone. Needs Zone:Read and DNS:Edit on the parent zone."
  type        = string
  sensitive   = true
}

variable "cloudflare_parent_domain" {
  description = <<EOF
The Cloudflare-managed parent zone that base_domain is a subdomain of (e.g.
`andrewsutliff.com` when base_domain is `okd.andrewsutliff.com`). Terraform
creates a public Route53 zone for base_domain and publishes NS records into this
Cloudflare zone to delegate it. Leave empty to skip automatic delegation and add
the NS records yourself.
EOF
  type        = string
  default     = ""
}

variable "manage_ingress_dns" {
  description = "Create the *.apps wildcard record in Cloudflare. Leave false for the first apply (the ingress load balancer does not exist until the cluster is up), then set true and re-apply."
  type        = bool
  default     = false
}

variable "ingress_router_lb_hostname" {
  description = "Optional override for the ingress (router-default) load balancer hostname used by the *.apps record. Leave empty to auto-discover the NLB by tag; set it explicitly if ingress uses a Classic ELB (which cannot be found via data.aws_lb)."
  type        = string
  default     = ""
}
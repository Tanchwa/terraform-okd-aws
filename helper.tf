locals {
  major_version   = join(".", slice(split(".", var.openshift_version), 0, 2))
  aws_azs         = (var.aws_azs != null) ? var.aws_azs : tolist([join("",[var.aws_region,"a"]),join("",[var.aws_region,"b"]),join("",[var.aws_region,"c"])])

  # OKD uses SCOS (CentOS Stream CoreOS). Prebuilt SCOS AMIs are only published
  # for us-east-1 and us-gov-west-1; for any other region set var.aws_ami to an
  # AMI you have copied into that region.
  scos_image      = jsondecode(data.http.images.body)["architectures"]["x86_64"]["images"]["aws"]["regions"][var.aws_region]["image"]
  rhcos_image     = var.aws_ami != "" ? var.aws_ami : local.scos_image
}

data "http" "images" {
  url = "https://raw.githubusercontent.com/openshift/installer/release-${local.major_version}/data/data/coreos/scos.json"
  request_headers = {
    Accept = "application/json"
  }
}
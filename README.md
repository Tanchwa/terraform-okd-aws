# Automated OKD v4 installation on AWS

This project automates the [OKD](https://okd.io) (the community distribution of Kubernetes that powers Red Hat OpenShift) installation on the Amazon AWS platform. It focuses on the User-provided infrastructure installation (UPI) where implementers provide pre-existing infrastructure including VMs, networking, load balancers, DNS configuration etc.

OKD runs on **SCOS** (CentOS Stream CoreOS) and, unlike licensed OpenShift, does **not** require a Red Hat pull secret. See [Notes on OKD](#notes-on-okd) below for the two constraints that matter most: the pull secret and the SCOS AMI region coverage.

* [Terraform Automation](#terraform-automation)
* [Infrastructure Architecture](#infrastructure-architecture)
* [Installation Procedure](#installation-procedure)
* [Airgapped installation](#airgapped-installation)
* [Removal procedure](#removal-procedure)
* [Advanced topics](#advanced-topics)

## Terraform Automation

This project uses mainly Terraform as infrastructure management and installation automation driver. All the user provisioned resource are created via the terraform scripts in this project.

### Prerequisites

1. To use Terraform automation, download the Terraform binaries [here](https://www.terraform.io/). The code here supports Terraform 0.15 or later.

   On MacOS, you can acquire it using [homebrew](brew.sh) using this command:

   ```bash
   brew install terraform
   ```

2. Install git

   ```bash
   sudo yum intall git-all
   git --version
   ```

4. Install wget command:

    - MacOS:
      ```
      brew install wget
      ```
    - Linux: (choose the command depending on your distribution)
      ```
      apt-get install wget
      yum install wget
      zypper install wget
      ```

6. Get the Terraform code

   ```bash
   git clone https://github.com/ibm-cloud-architecture/terraform-openshift4-aws.git
   ```

7. Prepare the DNS

   Public DNS for the cluster is managed in **Cloudflare**. You need a Cloudflare zone for your `base_domain` and an API token with `Zone:Read` and `DNS:Edit` on it (set via `cloudflare_api_token`). The internal `api-int` records are served from an AWS **private** Route53 hosted zone that this project creates and attaches to the cluster VPC — so no public Route53 zone is required. See [DNS (Cloudflare + private Route53)](#dns-cloudflare--private-route53).

8. Prepare AWS Account Access

   Please reference the [Required AWS Infrastructure components](https://docs.openshift.com/container-platform/4.6/installing/installing_aws/installing-aws-account.html) to setup your AWS account before installing OpenShift 4.

   We suggest to create an AWS IAM user dedicated for OpenShift installation with permissions documented above.
   On the bastion host, configure your AWS user credential as environment variables:

    ```bash
    export AWS_ACCESS_KEY_ID=RKXXXXXXXXXXXXXXX
    export AWS_SECRET_ACCESS_KEY=LXXXXXXXXXXXXXXXXXX/ng
    export AWS_DEFAULT_REGION=us-east-2
    ```

## Infrastructure Architecture

For detail on OpenShift UPI, please reference the following:

* [https://docs.openshift.com/container-platform/4.6/installing/installing_aws/installing-aws-customizations.html](https://docs.openshift.com/container-platform/4.6/installing/installing_aws/installing-aws-customizations.html)

The terraform code in this repository supports 3 installation modes:

- External facing cluster in a private network: ![External Open](img/openshift_aws_external.png)

- Internal cluster with internet access: ![Internal](img/openshift_aws_internal.png)

- Airgapped cluster with no access: ![Airgapped](img/openshift_aws_airgapped.png)

There are other installation modes that are possible with this terraform set, but we have not tested all the possible combinations, see [Advanced usage](#advanced-topics)

## Installation Procedure

This project installs the OpenShift 4 in several stages where each stage automates the provisioning of different components from infrastructure to OpenShift installation. The design is to provide the flexibility of different topology and infrastructure requirement.

1. The deployment assumes that you run the terraform deployment from a Linux based environment. This can be performed on an AWS-linux EC2 instance. The deployment machine has the following requirements:

    - git cli
    - terraform 0.15 or later
    - wget command
    - jq command

2. Deploy the OpenShift 4 cluster using the following modules in the folders:

 	- route53: generate a private hosted zone using route 53
	- install: Build the installation files, ignition configs and modify YAML files
  - vpc: Create the VPC, subnets, security groups and load balancers for the OpenShift cluster
	- iam: define AWS authorities for the masters and workers
	- bootstrap: main module to provision the bootstrap node and generates OpenShift installation files and resources
	- master: create master nodes manually (UPI)

	You can also provision all the components in a single terraform main module, to do that, you need to use a terraform.tfvars, that is copied from the terraform.tfvars.example file. The variables related to that are:

	Create a `terraform.tfvars` file with following content:

```
cluster_name = "okd4"
base_domain = "example.com"
openshift_pull_secret = "./fake_pull_secret.json"
openshift_version = "4.22.0-okd-scos.8"
cloudflare_api_token = "your-cloudflare-api-token"

aws_extra_tags = {
  "owner" = "admin"
  }
aws_region = "us-east-1"
aws_publish_strategy = "External"
```

|name | required  | description and value        |
|----------------|------------|--------------|
| `cluster_name` | yes  | The name of the OKD cluster you will install     |
| `base_domain`  | yes | The domain of the Cloudflare zone that public records are created in |
| `cloudflare_api_token` | yes | Cloudflare API token with `Zone:Read` + `DNS:Edit` on the `base_domain` zone |
| `manage_ingress_dns` | no | Set `true` (second apply, after the cluster is up) to create the `*.apps` wildcard in Cloudflare. Default `false`. |
| `ingress_router_lb_hostname` | no | Explicit ingress LB hostname for `*.apps`; leave empty to auto-discover the NLB by tag (needed if ingress is a Classic ELB). |
| `openshift_byo_dns` | no | Tells OKD that DNS is externally managed. Must stay `true` (default) with the Cloudflare integration. |
| `openshift_pull_secret` | no | Path to a pull secret file. OKD does not require a Red Hat entitlement — the bundled `./fake_pull_secret.json` is used by default. |
| `openshift_version` | yes | The OKD release tag to install, e.g. `4.22.0-okd-scos.8`. Valid tags are listed at https://github.com/okd-project/okd/releases  |
| `aws_region`   | yes  | AWS region that the VPC will be created in. Note that for an HA installation, the AWS selected region should have at least 3 availability zones. **SCOS bootimage AMIs are only published for `us-east-1` and `us-gov-west-1`; for any other region you must set `aws_ami`.** |
| `aws_ami` | no | Override the SCOS AMI for all nodes. Required for regions other than `us-east-1`/`us-gov-west-1` — copy a SCOS AMI into your region and set it here. |
| `aws_extra_tags`  | no  | AWS tag to identify a resource for example owner:myname     |
| `aws_azs` | no | list of availability zones to deploy VMs - default to the [`a`, `b`, `c`] |
| `openshift_ssh_key` | no | whether to use a specific public key  |
| `openshift_additional_trust_bundle` | no | additional trust bundle for accessing resources - ie proxy or repo | 
| `aws_publish_strategy` | no | Whether to publish the API endpoint externally - Default: "External" |
| `airgapped` | no | A map with enabled (true/false) and repository name - This must be used with `aws_publish_strategy` of `Internal` |
| `proxy_config` | no | To be implemented  |
| `use_ipv4` | no | To be implemented  |
| `use_ipv6` | no | To be implemented  |



See [Terraform documentation](https://www.terraform.io/intro/getting-started/variables.html) for the format of this file.

### Deploying the cluster

Initialize the Terraform:

```bash
terraform init
```

Run the terraform provisioning:

```bash
terraform plan
terraform apply
```

### Removing bootstrap node
 
Once the cluster is installed, the bootstrap node is no longer used at all. One of the indication that the bootstrap has been completed is that the API load balancer target group shows that the bootstrap address is `unhealthy`. 

```
terraform destroy -target=module.bootstrap.aws_instance.bootstrap
```



## Airgapped Installation

For performing a completely airgapped cluster, there are two capabilities that would not be available from the cluster's automation capabilities, the IAM and Route53 management access. The airgapped solution can address this by pre-creating the roles and secret that are needed for OpenShift to complete its functions, but the DNS update on Route53 must be performed manually after the installation.

Setting up the mirror repository using AWS ECR:

1. Create the repository

    ```
    aws ecr create-repository --repository-name ocp435
    ```

2. Prepare your credential to access the ECR repository (ie the credential only valid for 12 hrs)

    ```
    aws ecr get-login
    ```

    Extract the password token (`-p` argument) and create a Base64 string:

    ```
    echo "AWS:<token>" | base64 -w0
    ```

    Put that into your pull secret:

    ```
    {"353456611220.dkr.ecr.us-east-1.amazonaws.com":{"auth":"<base64string>","email":"abc@example.com"}}
    ```

3. Mirror quay.io and other OKD source into your repository

    ```
    export OCP_RELEASE="4.22.0-okd-scos.8"
    export LOCAL_REGISTRY='1234567812345678.dkr.ecr.us-east-1.amazonaws.com'
    export LOCAL_REPOSITORY='okd'
    export PRODUCT_REPO='okd'
    export LOCAL_SECRET_JSON='/home/ec2-user/fake_pull_secret.json'
    export RELEASE_NAME="scos-release"

    oc adm -a ${LOCAL_SECRET_JSON} release mirror --max-per-registry=1 \
       --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE} \
       --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
       --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}
    ```

4. Provide the certificate(s) for the registry in a file and refers that from the vars to be included in the `install-config.yaml`.

Once the mirror registry is created - use the terraform.tfvars similar to below:

```
cluster_name = "okd4"
base_domain = "example.com"
openshift_pull_secret = "./fake_pull_secret.json"
openshift_version = "4.22.0-okd-scos.8"

aws_ami = "ami-06f85a7940faa3217"
aws_extra_tags = {
  "owner" = "admin"
  }
aws_azs = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
  ]
aws_region = "us-east-1"
aws_publish_strategy = "Internal"
airgapped = {
  enabled = true
  repository = "1234567812345678.dkr.ecr.us-east-1.amazonaws.com/ocp435"
  cabundle = "./cabundle"
}
```

**Note**: To use `airgapped.enabled` of `true` must be done with `aws_publish_strategy` of `Internal` otherwise the deployment will fail. Also ECR does not allow for unauthenticated image pulls, additional IAM policies must be defined and attached to the nodes to be able to pull from ECR.

Create your cluster and then associate the private Hosted Zone Record in Route53 with the loadbalancer for the `*.apps.<cluster>.<domain>`.  

## Removal procedure

To delete the cluster - `terraform destroy` can be implemented.
The following items are not deleted (and may stop destroy from being successful):
- EBS volumes from the gp2 storage classes
- Public zone DNS updates
- Custom compute nodes that are not the initial worker nodes

## DNS (Cloudflare + private Route53)

Public DNS is managed in **Cloudflare**; internal split-horizon DNS stays in an AWS **private** Route53 hosted zone. The cluster is installed as BYO DNS (`openshift_byo_dns = true`, the default) so the in-cluster ingress/DNS operators do not try to manage records themselves.

What Terraform creates:

| Record | Location | Target |
|--------|----------|--------|
| `api.<cluster>.<domain>` | Cloudflare (public) | external API NLB (when `aws_publish_strategy = "External"`) |
| `api-int.<cluster>.<domain>` | Route53 private zone (in-VPC) | internal API NLB |
| `api.<cluster>.<domain>` | Route53 private zone (in-VPC) | internal API NLB (split-horizon) |
| `*.apps.<cluster>.<domain>` | Cloudflare (public) | ingress LB — only when `manage_ingress_dns = true` |

Provider configuration is a single token:

```hcl
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
```

The zone is resolved by lookup rather than hardcoded:

```hcl
data "cloudflare_zones" "this" { name = var.base_domain }
# local.cloudflare_zone_id = data.cloudflare_zones.this.result[0].id
```

### The `*.apps` wildcard (two-phase apply)

The ingress load balancer does not exist until the cluster is up, so create `*.apps` on a **second apply**:

1. First `terraform apply` with `manage_ingress_dns = false` — brings up the cluster (creates `api` / `api-int`).
2. Once the cluster is running and the router LB exists, set `manage_ingress_dns = true` and `terraform apply` again. The module discovers the `router-default` NLB by tag and points `*.apps` at it.

If your default ingress uses a **Classic ELB** (older behavior; `data.aws_lb` only finds NLBs), pass the LB hostname explicitly instead:

```bash
oc -n openshift-ingress get svc router-default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

```hcl
manage_ingress_dns         = true
ingress_router_lb_hostname = "<that-hostname>"
```

## Notes on OKD

This project deploys **OKD**, the community distribution, rather than licensed Red Hat OpenShift. A few differences to be aware of:

- **Installer/client source**: the `openshift-install` and `oc` binaries are downloaded from the OKD GitHub releases (`https://github.com/okd-project/okd/releases`) rather than the Red Hat mirror. Set `openshift_version` to a release tag such as `4.22.0-okd-scos.8`.
- **Pull secret**: OKD does not require a Red Hat entitlement. The bundled `fake_pull_secret.json` (`{"auths":{"fake":{"auth":"..."}}}`) is used by default. You can still point `openshift_pull_secret` at a real Red Hat pull secret if you need to pull entitled content.
- **Node OS / AMI**: OKD nodes run SCOS (CentOS Stream CoreOS). The SCOS AMI is resolved automatically from the installer stream metadata, **but prebuilt SCOS AMIs are only published for `us-east-1` and `us-gov-west-1`**. To deploy in any other region, copy a SCOS AMI into that region (e.g. `aws ec2 copy-image`) and set `aws_ami` to the resulting AMI ID.
- **Network type**: OKD 4.19+ only supports `OVNKubernetes` (the legacy `OpenShiftSDN` plugin has been removed).

## Advanced topics

Additional configurations and customization of the implementation can be performed by changing some of the default variables.
You can check the variable contents in the following terraform files:

- variable-aws.tf: AWS related customization, such as machine sizes and network changes
- config.tf: common installation variables for installation (not cloud platform specific)

**Note**: Not all possible combinations of options has been tested - use them at your own risk. 

# RunsOn Terraform Modules

This repository publishes RunsOn Terraform modules for AWS:

- [RunsOn Flex](https://github.com/runs-on/terraform-aws-runs-on/blob/main/modules/flex/README.md): full webhook-driven control plane for ephemeral GitHub Actions runners
- [RunsOn Fleet](https://github.com/runs-on/terraform-aws-runs-on/blob/main/modules/fleet/README.md): pool-oriented runner control plane for scale-set-style deployments

The Terraform Registry root is a landing page. Use the Flex module explicitly:

```hcl
module "runs_on_flex" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.0.4"
}
```

## Complete Flex Example

This example creates a VPC with public and private subnets, adds a free S3 gateway endpoint for private runners, and deploys RunsOn Flex.

```hcl
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on-v3"
}

variable "github_organization" {
  description = "GitHub organization or username for RunsOn integration"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

variable "email" {
  description = "Email address for cost and alert reports"
  type        = string
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.stack_name}-vpc"
  cidr = "10.17.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.17.0.0/20", "10.17.16.0/20"]
  private_subnets = ["10.17.128.0/20", "10.17.144.0/20"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }
}

module "runs_on_flex" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.0.4"

  stack_name = var.stack_name

  github_organization = var.github_organization
  license_key         = var.license_key
  email               = var.email

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  private_mode        = "true"
  enable_efs          = true
  enable_ecr          = true
  enable_admin_routes = true
}

output "getting_started" {
  description = "RunsOn post-apply setup instructions"
  value       = module.runs_on_flex.stack.getting_started
}

output "nat_ips" {
  description = "Public NAT Gateway IPs used by private runners"
  value       = module.vpc.nat_public_ips
}
```

After `terraform apply`, print the setup instructions:

```shell
terraform output -raw getting_started
```

The NAT Gateway is required for this private-subnet example because the Flex worker and runners need outbound internet access to GitHub and other public services.

## Git Source

If you consume directly from Git, use the same subdirectory pattern:

```hcl
module "runs_on_flex" {
  source = "git::https://github.com/runs-on/terraform-aws-runs-on.git//modules/flex?ref=main"
}
```

Older published tags that used the mirror root or `//flex` path remain valid for those historical versions. Current documentation and releases use `//modules/flex`.

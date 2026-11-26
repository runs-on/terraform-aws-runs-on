# Basic RunsOn Deployment Example
# This demonstrates the standard configuration with all smart defaults

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

# The Region's own zones, not opted-in Local or Wavelength Zones. No state
# filter: a zone AWS reports impaired would otherwise drop out of the list and
# move the later subnets to other zones, which replaces them.
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# VPC Module - Creates networking infrastructure
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.stack_name}-vpc"
  cidr = var.vpc_cidr

  # Up to three zones: more zones give runners more EC2 capacity. In a Region
  # with two (such as us-west-1), the third subnet goes to the first zone.
  azs             = slice(data.aws_availability_zones.available.names, 0, min(3, length(data.aws_availability_zones.available.names)))
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # NAT Gateway for private subnets (only if private networking enabled)
  enable_nat_gateway = length(var.private_subnet_cidrs) > 0
  single_nat_gateway = true

  # Internet connectivity
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# RunsOn Module - Deploys RunsOn infrastructure with smart defaults
module "runs_on" {
  source = "../../"

  # Stack configuration
  stack_name = var.stack_name

  # Required: GitHub and License
  github_organization = var.github_organization
  license_key         = var.license_key
  email               = var.email

  # Required: Network configuration (BYOV - Bring Your Own VPC)
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  # Optional: Security groups (if not provided, module creates them automatically)
  # security_group_ids = ["sg-xxxxx"]
}

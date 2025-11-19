# Private Networking RunsOn Deployment Example
# Demonstrates enabling private networking with 4 modes

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module - Creates networking infrastructure with private subnets
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.stack_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # NAT Gateway required for private networking
  enable_nat_gateway = true
  single_nat_gateway = true # Set to false for HA across AZs

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "production"
    ManagedBy   = "OpenTofu"
    Project     = "RunsOn"
  }
}

# RunsOn Module - With private networking enabled
module "runs_on" {
  source = "../../"

  # Stack configuration
  stack_name = var.stack_name

  # Required: GitHub and License
  github_organization = var.github_organization
  license_key         = var.license_key
  email               = var.email

  # Required: Network configuration
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  # Feature: Private Networking Mode
  # Options:
  #   "false"  - Disabled (default)
  #   "true"   - Opt-in with label: runners can use private=true label
  #   "always" - Default with opt-out: runners use private by default, can opt-out with private=false
  #   "only"   - Forced: all runners must use private subnets
  private_mode = var.private_mode
}

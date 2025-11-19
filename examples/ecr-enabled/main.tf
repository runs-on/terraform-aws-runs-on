# ECR-Enabled RunsOn Deployment Example
# Demonstrates enabling ECR for ephemeral container registry cache

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

# VPC Module - Creates networking infrastructure
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.stack_name}-vpc"
  cidr = var.vpc_cidr

  azs            = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets = var.public_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "production"
    ManagedBy   = "OpenTofu"
    Project     = "RunsOn"
  }
}

# RunsOn Module - With ECR enabled
module "runs_on" {
  source = "../../"

  # Stack configuration
  stack_name = var.stack_name

  # Required: GitHub and License
  github_organization = var.github_organization
  license_key         = var.license_key
  email               = var.email

  # Required: Network configuration
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnets

  # Feature: ECR Ephemeral Registry
  # Enables private container registry for Docker BuildKit cache
  enable_ecr = true
}

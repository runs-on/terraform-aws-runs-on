# Full-Featured RunsOn Deployment Example
# Demonstrates all RunsOn features enabled together

terraform {
  required_version = ">= 1.6.0"

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

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module - Creates full networking infrastructure
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.stack_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # NAT Gateway for private networking
  enable_nat_gateway = true
  single_nat_gateway = false # Multi-AZ for HA

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Endpoints
  # Enable only if you're using private networking in RunsOn for full intra-VPC traffic to AWS APIs (avoids NAT Gateway data transfer costs).

  # S3 gateway endpoint is free and recommended
  enable_s3_endpoint = true

  # ECR endpoints are useful if you push/pull lots of images (enable_ecr = true)
  enable_ecr_api_endpoint = false # For ECR API calls
  enable_ecr_dkr_endpoint = false # For ECR image pulls

  # Interface endpoints below cost ~$7/mo each.
  enable_ec2_endpoint         = false # For EC2 API calls
  enable_logs_endpoint        = false # For CloudWatch Logs
  enable_ssm_endpoint         = false # For SSM access
  enable_ssmmessages_endpoint = false # For SSM Session Manager
}

# RunsOn Module - All features enabled
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

  # Feature: Private Networking (opt-in mode)
  private_mode = "true"

  # Feature: EFS Shared Storage
  enable_efs = true

  # Feature: ECR Ephemeral Registry
  enable_ecr = true

  # Feature: CloudWatch Dashboard for monitoring
  enable_dashboard = true

  # Resource protection
  prevent_destroy_optional_resources = var.prevent_destroy_optional_resources

  # All other settings use smart defaults from CloudFormation
}

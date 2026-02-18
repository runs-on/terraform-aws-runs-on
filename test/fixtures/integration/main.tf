# Integration test fixture
# Combines VPC + RunsOn module in a single state for persistence across runs.
# S3 buckets survive `terraform destroy` (force_destroy = false), preserving
# the GitHub App registration (app.json) for automated integration testing.
#
# First run: requires manual app registration at the App Runner URL.
# Subsequent runs: fully automated (app.json persists in config bucket).
#
# For CI with S3 backend, create a backend.tf file:
#   terraform { backend "s3" { bucket = "...", key = "...", region = "..." } }

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      TestFramework = "terratest"
      ManagedBy     = "terratest-integration"
      AutoCleanup   = "true"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "${var.stack_name}-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  public_subnets = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "runs_on" {
  source = "../../../"

  stack_name          = var.stack_name
  github_organization = var.github_organization
  license_key         = var.license_key
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnets
  email               = var.email
  environment         = var.environment

  force_destroy_buckets              = var.force_destroy_buckets
  force_delete_ecr                   = true
  prevent_destroy_optional_resources = false
  log_retention_days                 = 1
  cache_expiration_days              = 1
  app_cpu                            = 1024
  app_memory                         = 2048
}

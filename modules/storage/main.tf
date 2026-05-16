# modules/storage/main.tf
# Storage module orchestration for RunsOn - S3 buckets for config, cache, and logging

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}

# Local variables
locals {
  common_tags = var.tags
}

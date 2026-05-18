# modules/compute/main.tf
# Compute module orchestration for RunsOn - EC2 launch templates and IAM roles

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Local variables
locals {
  log_group_name = "${var.stack_name}/ec2/instances"

  common_tags = var.tags
}

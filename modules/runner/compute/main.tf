terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

locals {
  log_group_name = "${var.stack_name}/ec2/instances"

  common_tags = var.tags
}

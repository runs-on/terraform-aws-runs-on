terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.39"
    }
  }
}

locals {
  partition      = data.aws_partition.current.partition
  log_group_name = "${var.stack_name}/ec2/instances"

  common_tags = var.tags
}

data "aws_partition" "current" {}

data "aws_service_principal" "ec2" {
  service_name = "ec2"
}

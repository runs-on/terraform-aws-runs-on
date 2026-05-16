# modules/optional/main.tf
# Optional module orchestration for RunsOn - EFS and ECR

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
  common_tags = var.tags
}

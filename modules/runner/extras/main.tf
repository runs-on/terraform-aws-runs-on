terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}

locals {
  common_tags                        = var.tags
  account_regional_cache_bucket_name = "${var.stack_name}-cache-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45"
    }
  }
}

# Deploy the shared AMI syncer once per account+region. The provider region IS the
# destination region — copies land here from var.source_region.
provider "aws" {
  region = "ap-northeast-2"
}

# Pass the product stack's values as plain inputs (no remote-state coupling):
# - common_tags: the stack's tags map, so copies are tagged at create time (SCP compliance).
# - kms_key_id: how the copied snapshot is encrypted at rest (see options below).
module "ami_sync" {
  source = "../.."

  enabled    = true
  stack_name = "runs-on-shared"

  images = [
    { name = "runs-on-v2.2-ubuntu24-full-x64-*", architecture = "x86_64" },
    { name = "runs-on-v2.2-ubuntu24-full-arm64-*", architecture = "arm64" },
  ]

  # Encryption of the copied snapshot (pick one):
  #   - "" (omit): no explicit encryption; inherit the Region's EBS settings.
  #   - "default": encrypt with the region's EBS default key (zero setup).
  #   - "aws/ebs": encrypt with the AWS-managed EBS key.
  #   - "<key ARN>": encrypt with a specific CMK.
  kms_key_id = "default"

  common_tags = {
    Team        = "platform"
    Environment = "production"
  }
}

output "ami_sync_function_name" {
  value = module.ami_sync.function_name
}

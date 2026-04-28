# versions.tf
# OpenTofu version constraints and provider configuration

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

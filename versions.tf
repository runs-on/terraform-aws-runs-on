# versions.tf
# OpenTofu version constraints and provider configuration

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}

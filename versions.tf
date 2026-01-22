# versions.tf
# OpenTofu version constraints and provider configuration

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
    github = {
      source  = "integrations/github"
      version = ">= 5.0"
    }
  }
}

provider "github" {
  # Use unauthenticated access - github_ip_ranges uses a public API endpoint
  # and doesn't require a token. Setting empty token prevents the provider from
  # using GITHUB_TOKEN env var (which fails in GitHub Actions due to limited permissions)
  token = ""
}
# Root Terragrunt configuration
# This file contains common settings shared across all test scenarios

locals {
  # AWS region for all tests
  aws_region = "us-east-1"

  # Generate unique test ID for resource naming
  test_id = run_cmd("--terragrunt-quiet", "date", "+%s")

  # Common tags applied to all resources
  common_tags = {
    TestFramework = "terratest"
    TestID        = local.test_id
    ManagedBy     = "terragrunt"
    AutoCleanup   = "true"
    Environment   = "test"
  }
}

# Configure local state for tests (no remote backend needed)
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

# Auto-generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = ${jsonencode(local.common_tags)}
  }
}
EOF
}

# Common inputs available to all children
# These can be overridden in scenario-specific terragrunt.hcl files
inputs = {
  # Test-specific defaults to reduce costs
  log_retention_days          = 1
  cache_expiration_days       = 1
  detailed_monitoring_enabled = false

  # Minimal App Runner sizing for tests
  app_cpu    = 1024  # 1 vCPU
  app_memory = 2048  # 2 GB

  # Environment
  environment = "test"
}

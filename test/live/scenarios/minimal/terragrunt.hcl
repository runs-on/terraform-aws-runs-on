# Minimal configuration scenario
# Tests the bare minimum required to deploy the runs-on module

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../"  # Root module
}

dependency "vpc" {
  config_path = "../../_shared/vpc"

  # Mock outputs for plan/validate
  mock_outputs = {
    vpc_id         = "vpc-mock123"
    public_subnets = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  stack_name          = "test-minimal-${get_env("TEST_ID", "default")}"
  github_organization = get_env("GITHUB_ORG", "test-org")
  license_key         = get_env("RUNS_ON_LICENSE_KEY", "test-license-key")

  # VPC configuration
  vpc_id            = dependency.vpc.outputs.vpc_id
  public_subnet_ids = dependency.vpc.outputs.public_subnets

  # Minimal features (all optional features disabled)
  enable_efs = false
  enable_ecr = false

  # No private networking
  # private_subnet_ids not specified
}

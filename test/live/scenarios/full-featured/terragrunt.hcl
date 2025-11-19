# Full-featured scenario
# Tests deployment with all features enabled
# NOTE: This requires NAT gateway which costs money!

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../"
}

dependency "vpc" {
  config_path = "../../_shared/vpc"

  mock_outputs = {
    vpc_id          = "vpc-mock123"
    public_subnets  = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    private_subnets = ["subnet-mock4", "subnet-mock5", "subnet-mock6"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  stack_name          = "test-full-${get_env("TEST_ID", "default")}"
  github_organization = get_env("GITHUB_ORG", "test-org")
  license_key         = get_env("RUNS_ON_LICENSE_KEY", "test-license-key")

  # VPC configuration - both public and private subnets
  vpc_id             = dependency.vpc.outputs.vpc_id
  public_subnet_ids  = dependency.vpc.outputs.public_subnets
  private_subnet_ids = dependency.vpc.outputs.private_subnets

  # All optional features enabled
  enable_efs = true
  enable_ecr = true

  # Enhanced monitoring for testing
  detailed_monitoring_enabled = false  # Keep false to reduce costs in tests
  enable_cost_reports         = false  # Keep false to avoid emails during tests

  # This should create:
  # - 4 launch templates (Linux/Windows x Public/Private)
  # - EFS file system with mount targets
  # - ECR repository
  # - VPC connector for App Runner
  # - All IAM policies
}

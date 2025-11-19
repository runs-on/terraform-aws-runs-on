# Private networking scenario
# Tests deployment with both public and private subnets
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
  stack_name          = "test-private-${get_env("TEST_ID", "default")}"
  github_organization = get_env("GITHUB_ORG", "test-org")
  license_key         = get_env("RUNS_ON_LICENSE_KEY", "test-license-key")

  # VPC configuration - both public and private subnets
  vpc_id             = dependency.vpc.outputs.vpc_id
  public_subnet_ids  = dependency.vpc.outputs.public_subnets
  private_subnet_ids = dependency.vpc.outputs.private_subnets

  # Optional features disabled for this scenario
  enable_efs = false
  enable_ecr = false

  # This should create 4 launch templates (Linux/Windows x Public/Private)
}

# Public networking only scenario
# Tests deployment with only public subnets (no private networking)

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../"
}

dependency "vpc" {
  config_path = "../../_shared/vpc"

  mock_outputs = {
    vpc_id         = "vpc-mock123"
    public_subnets = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  stack_name          = "test-public-${get_env("TEST_ID", "default")}"
  github_organization = get_env("GITHUB_ORG", "test-org")
  license_key         = get_env("RUNS_ON_LICENSE_KEY", "test-license-key")

  # VPC configuration - public only
  vpc_id            = dependency.vpc.outputs.vpc_id
  public_subnet_ids = dependency.vpc.outputs.public_subnets

  # Optional features disabled
  enable_efs = false
  enable_ecr = false

  # Explicitly test with auto-created security group
  security_group_ids = []
}

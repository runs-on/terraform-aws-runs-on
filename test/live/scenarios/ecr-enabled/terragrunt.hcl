# ECR enabled scenario
# Tests deployment with private ECR repository

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
  stack_name          = "test-ecr-${get_env("TEST_ID", "default")}"
  github_organization = get_env("GITHUB_ORG", "test-org")
  license_key         = get_env("RUNS_ON_LICENSE_KEY", "test-license-key")

  # VPC configuration
  vpc_id            = dependency.vpc.outputs.vpc_id
  public_subnet_ids = dependency.vpc.outputs.public_subnets

  # EFS disabled, ECR enabled
  enable_efs = false
  enable_ecr = true

  # This should create:
  # - ECR repository
  # - Lifecycle policy for image cleanup
  # - IAM policies for ECR access
}

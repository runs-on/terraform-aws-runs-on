# Shared VPC configuration for test scenarios
# This creates a VPC that can be used by multiple test scenarios

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=5.0.0"
}

inputs = {
  name = "test-runs-on-vpc-${get_env("TEST_ID", "default")}"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  # Only create NAT gateway if explicitly requested (costs money!)
  enable_nat_gateway = get_env("ENABLE_NAT", "false") == "true"
  single_nat_gateway = true

  # DNS settings
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags
  tags = {
    Name        = "test-runs-on-vpc"
    Purpose     = "terratest"
    AutoCleanup = "true"
  }
}

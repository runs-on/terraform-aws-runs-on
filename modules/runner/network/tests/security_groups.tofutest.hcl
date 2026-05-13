mock_provider "aws" {}

variables {
  stack_name         = "test-plan"
  vpc_id             = "vpc-12345678"
  public_subnet_ids  = ["subnet-public-a"]
  private_subnet_ids = ["subnet-private-a"]
  private_mode       = "false"
  ssh_allowed        = false
  ssh_cidr_range     = "10.0.0.0/8"
  tags               = {}
}

run "creates_security_group_when_none_provided" {
  command = plan

  variables {
    security_group_ids = []
  }

  assert {
    condition     = length(aws_security_group.runners) == 1
    error_message = "Network module should create a runner security group when no security_group_ids are provided."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.all_ipv4) == 1 && length(aws_vpc_security_group_egress_rule.all_ipv6) == 1
    error_message = "Network module should create default egress rules with the managed security group."
  }
}

run "skips_security_group_when_provided" {
  command = plan

  variables {
    security_group_ids = ["sg-provided"]
  }

  assert {
    condition     = length(aws_security_group.runners) == 0
    error_message = "Network module should not create a runner security group when security_group_ids are provided."
  }

  assert {
    condition     = length(output.network.security_group_ids) == 1 && output.network.security_group_ids[0] == "sg-provided"
    error_message = "Network output should preserve the provided security group IDs."
  }
}

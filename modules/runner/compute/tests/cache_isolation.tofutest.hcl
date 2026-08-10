mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.com"
      partition  = "aws"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      unique_id = "AROATESTSTACKROLEID"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/test-stack-ec2-instance-profile"
    }
  }
}

variables {
  region                  = "us-east-1"
  account_id              = "123456789012"
  stack_name              = "test-stack"
  cost_allocation_tag     = "runs-on-stack-name"
  log_retention_days      = 7
  permission_boundary_arn = ""
  app_tag                 = "v0.0.0-test"
  bootstrap_tag           = "v0.0.0-test"
  ipv6_enabled            = false
  runner_max_runtime      = 360
  tags = {
    Environment          = "test"
    "runs-on-stack-name" = "test-stack"
  }

  network = {
    vpc_id             = "vpc-12345678"
    private_mode       = "false"
    public_subnet_ids  = ["subnet-12345678"]
    private_subnet_ids = []
    security_group_ids = ["sg-12345678"]
  }

  extras = {
    cache = {
      bucket_id   = "test-stack-cache"
      bucket_arn  = "arn:aws:s3:::test-stack-cache"
      bucket_name = "test-stack-cache"
    }
    efs = {
      enabled           = false
      file_system_id    = ""
      file_system_arn   = ""
      file_system_dns   = ""
      security_group_id = ""
    }
    ecr = {
      enabled         = false
      repository_arn  = ""
      repository_name = ""
      repository_url  = ""
    }
    pull_through_cache = {
      enabled           = false
      registry_url      = ""
      docker_hub_prefix = ""
      rules             = {}
    }
  }
}

run "cache_isolation_disabled_grants_legacy_cache_access" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role_policy.ec2_s3_access.policy, "arn:aws:s3:::test-stack-cache/cache/*")
    error_message = "Without cache isolation, runners keep direct access to the cache/* prefix."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.ec2_s3_access.policy, "runs-on-cache-brokered")
    error_message = "Without cache isolation, no tag-gated cache statements should be present."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.ec2_instance.assume_role_policy).Statement) == 1
    error_message = "Without cache isolation, only the EC2 service should be trusted to assume the runner role."
  }
}

run "cache_isolation_enabled_requires_brokered_credentials" {
  command = plan

  variables {
    enable_cache_isolation = true
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.ec2_s3_access.policy, "arn:aws:s3:::test-stack-cache/cache/*")
    error_message = "With cache isolation, the broad cache/* object grant must be gone."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.ec2_s3_access.policy, "runs-on-cache-brokered")
    error_message = "With cache isolation, direct cache access should not contain broker session grants; those live in the scoped broker policy."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.ec2_scoped_cache_broker.policy, "scoped-cache/*")
    error_message = "With cache isolation, the scoped cache prefix policy must be present."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.ec2_scoped_cache_broker.policy, "function:test-stack-cache-broker")
    error_message = "With cache isolation, runners must be able to invoke the broker Lambda."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.ec2_instance.assume_role_policy).Statement) == 2
    error_message = "With cache isolation, the broker role must be trusted to assume+tag the runner role."
  }
}

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

# Default path: the AWS-managed AmazonSSMManagedInstanceCore stays attached and no
# inline override is created, so existing deployments are unaffected.
run "attaches_managed_ssm_policy_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.ec2_ssm) == 1
    error_message = "The AWS-managed SSM policy should remain attached by default."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_ssm_override) == 0
    error_message = "No inline SSM override policy should exist by default."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ec2_ssm[0].policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The default SSM attachment should be AmazonSSMManagedInstanceCore."
  }
}

# Override path: supplying a policy document detaches the managed policy and
# attaches the supplied document verbatim as an inline policy instead.
run "override_replaces_managed_ssm_policy" {
  command = plan

  variables {
    runner_ssm_policy_override_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ScopedGetParameter\",\"Effect\":\"Allow\",\"Action\":[\"ssm:GetParameter\",\"ssm:GetParameters\"],\"Resource\":\"arn:aws:ssm:us-east-1:123456789012:parameter/test/*\"}]}"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ec2_ssm) == 0
    error_message = "The AWS-managed SSM policy should be detached when an override is supplied."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_ssm_override) == 1
    error_message = "Exactly one inline SSM override policy should be created when an override is supplied."
  }

  assert {
    condition     = aws_iam_role_policy.ec2_ssm_override[0].name == "SSMManagedInstanceCoreOverride"
    error_message = "The inline SSM override policy should use the expected name."
  }

  assert {
    condition     = aws_iam_role_policy.ec2_ssm_override[0].policy == var.runner_ssm_policy_override_json
    error_message = "The inline SSM override policy should carry the supplied policy document verbatim."
  }
}

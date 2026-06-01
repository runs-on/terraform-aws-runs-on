mock_provider "aws" {
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
      enabled                = false
      registry_url           = ""
      docker_hub_transparent = false
      rules                  = {}
    }
  }
}

run "does_not_create_bedrock_policy_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.ec2_bedrock_access) == 0
    error_message = "Bedrock access policy should not be created unless enable_bedrock is true."
  }
}

run "enable_bedrock_creates_expected_policy" {
  command = plan

  variables {
    enable_bedrock = true
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_bedrock_access) == 1
    error_message = "enable_bedrock should create exactly one Bedrock access policy."
  }

  assert {
    condition     = aws_iam_role_policy.ec2_bedrock_access[0].name == "BedrockAccess"
    error_message = "Bedrock access policy should use the expected policy name."
  }

  assert {
    condition = alltrue([
      for action in [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListInferenceProfiles",
      ] : contains(jsondecode(aws_iam_role_policy.ec2_bedrock_access[0].policy).Statement[0].Action, action)
    ])
    error_message = "Bedrock access policy should include the expected Bedrock actions."
  }

  assert {
    condition = alltrue([
      for resource in [
        "arn:aws:bedrock:*:*:foundation-model/*",
        "arn:aws:bedrock:*:*:inference-profile/*",
        "arn:aws:bedrock:*:*:application-inference-profile/*",
      ] : contains(jsondecode(aws_iam_role_policy.ec2_bedrock_access[0].policy).Statement[0].Resource, resource)
    ])
    error_message = "Bedrock access policy should include the expected Bedrock resource scopes."
  }
}

run "runner_custom_policy_arn_attaches_to_instance_role" {
  command = plan

  variables {
    runner_custom_policy_arn = "arn:aws:iam::123456789012:policy/RunsOnRunnerCustom"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ec2_custom) == 1
    error_message = "runner_custom_policy_arn should create one custom runner policy attachment."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ec2_custom[0].policy_arn == "arn:aws:iam::123456789012:policy/RunsOnRunnerCustom"
    error_message = "custom runner policy attachment should use the configured policy ARN."
  }
}

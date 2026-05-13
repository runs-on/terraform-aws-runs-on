mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      user_id    = "AIDATEST"
    }
  }

  mock_data "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
      key_id = "12345678-1234-1234-1234-123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name   = "us-east-1"
      region = "us-east-1"
    }
  }

  mock_resource "aws_api_gateway_rest_api" {
    defaults = {
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:api123"
      id            = "api123"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:123456789012:rule/mock"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-east-1:123456789012:table/mock"
    }
  }

  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:123456789012:repository/mock"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/mock"
    }
  }

  mock_resource "aws_efs_file_system" {
    defaults = {
      arn      = "arn:aws:elasticfilesystem:us-east-1:123456789012:file-system/fs-12345678"
      dns_name = "fs-12345678.efs.us-east-1.amazonaws.com"
      id       = "fs-12345678"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn       = "arn:aws:iam::123456789012:role/mock"
      unique_id = "AROATEST"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:123456789012:function:mock"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:mock/invocations"
    }
  }

  mock_resource "aws_resourcegroups_group" {
    defaults = {
      arn = "arn:aws:resource-groups:us-east-1:123456789012:group/mock"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn    = "arn:aws:s3:::mock"
      bucket = "mock"
      id     = "mock"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:123456789012:mock"
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/mock"
    }
  }

  mock_resource "aws_wafv2_ip_set" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:regional/ipset/mock/abcd1234"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/mock/abcd1234"
    }
  }
}

variables {
  github_organization                = "test-org"
  license_key                        = "test-license-key"
  vpc_id                             = "vpc-12345678"
  public_subnet_ids                  = ["subnet-11111111"]
  email                              = "test@example.com"
  stack_name                         = "test-plan"
  environment                        = "test"
  app_image                          = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:test"
  app_tag                            = "test"
  force_destroy_buckets              = true
  prevent_destroy_optional_resources = false
}

run "baseline_identity_and_outputs" {
  command = plan

  assert {
    condition     = output.stack.aws_account_id == "123456789012"
    error_message = "stack output should use mocked AWS account identity."
  }

  assert {
    condition     = output.stack.aws_region == "us-east-1"
    error_message = "stack output should use mocked AWS region."
  }

  assert {
    condition     = output.platform.optional_features.efs.enabled == false && output.platform.optional_features.ecr.enabled == false
    error_message = "baseline optional features should be disabled."
  }
}

run "private_mode_delay_creates_nat_wait" {
  command = plan

  variables {
    private_mode       = "true"
    private_subnet_ids = ["subnet-22222222"]
    private_mode_delay = "60s"
  }

  assert {
    condition     = time_sleep.wait_for_nat[0].create_duration == "60s"
    error_message = "private_mode_delay should create the NAT wait timer."
  }
}

run "invalid_capacity_provider_is_rejected" {
  command = plan

  variables {
    app_capacity_provider = "spot"
  }

  expect_failures = [var.app_capacity_provider]
}

run "app_force_new_deployment_flows_to_runtime" {
  command = plan

  variables {
    app_force_new_deployment = true
  }

  assert {
    condition     = local.flex_runtime.force_new_deployment == true
    error_message = "app_force_new_deployment should flow into the runtime config."
  }
}

run "empty_public_subnets_rejected_unless_private_only" {
  command = plan

  variables {
    public_subnet_ids  = []
    private_mode       = "true"
    private_subnet_ids = ["subnet-22222222"]
  }

  expect_failures = [terraform_data.validate_public_subnets]
}

run "private_only_allows_empty_public_subnets" {
  command = plan

  variables {
    public_subnet_ids  = []
    private_mode       = "only"
    private_subnet_ids = ["subnet-22222222"]
  }

  assert {
    condition     = output.platform.networking.private_mode == "only"
    error_message = "private_mode=only should plan without public subnets."
  }
}

run "private_only_efs_uses_private_subnets" {
  command = plan

  variables {
    enable_efs         = true
    public_subnet_ids  = []
    private_mode       = "only"
    private_subnet_ids = ["subnet-private-a", "subnet-private-b"]
  }

  assert {
    condition     = local.efs_mount_target_subnet_ids[0] == "subnet-private-a"
    error_message = "private-only EFS should use the first private subnet."
  }

  assert {
    condition     = local.efs_mount_target_subnet_ids[1] == "subnet-private-b"
    error_message = "private-only EFS should use the second private subnet."
  }
}

run "ghes_managed_waf_requires_public_ingress_acl" {
  command = plan

  variables {
    enable_waf            = true
    github_enterprise_url = "https://ghe.example.com"
  }

  expect_failures = [check.ghes_waf_requires_public_ingress_web_acl]
}

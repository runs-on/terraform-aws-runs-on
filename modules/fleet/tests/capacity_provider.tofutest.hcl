mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/test-plan-ec2-instance-profile"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-plan-role"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock"
    }
  }
}

variables {
  stack_name             = "test-plan"
  github_enterprise_pat  = "ghp_test"
  github_base_url        = "https://github.com"
  github_enterprise_name = "test-enterprise"
  license_key            = "test-license"
  email                  = "alerts@example.com"
  environment            = "test"
  vpc_id                 = "vpc-12345678"
  public_subnet_ids      = ["subnet-11111111"]

  runners = {
    small-x64 = {
      cpu    = 2
      ram    = 4
      family = ["c7"]
      image  = "ubuntu24-full-x64"
    }
  }

  fleets = {
    default = {
      runner = "small-x64"
    }
  }
}

run "defaults_to_fargate_capacity_provider" {
  command = plan

  assert {
    condition     = length(local.fleet_catalog.images) == 0
    error_message = "Fleet should not require users to define built-in image specs."
  }

  assert {
    condition     = local.fleet_catalog.runners.small-x64.image == "ubuntu24-full-x64"
    error_message = "Fleet should preserve runner references to built-in image names."
  }

  assert {
    condition     = local.fleet_runtime.capacity_provider == "FARGATE"
    error_message = "Fleet should default to the FARGATE capacity provider."
  }
}

run "can_use_fargate_spot_capacity_provider" {
  command = plan

  variables {
    app_capacity_provider = "fargate_spot"
  }

  assert {
    condition     = local.fleet_runtime.capacity_provider == "FARGATE_SPOT"
    error_message = "Fleet should pass FARGATE_SPOT to the runtime service."
  }
}

run "accepts_step_security_integration_key" {
  command = plan

  variables {
    integration_step_security_api_key = "step-security-secret"
  }

  assert {
    condition     = nonsensitive(var.integration_step_security_api_key) == "step-security-secret"
    error_message = "Fleet should accept the StepSecurity integration key."
  }
}

run "rejects_invalid_capacity_provider" {
  command = plan

  variables {
    app_capacity_provider = "spot"
  }

  expect_failures = [var.app_capacity_provider]
}

run "rejects_empty_stack_name" {
  command = plan

  variables {
    stack_name = ""
  }

  expect_failures = [var.stack_name]
}

run "rejects_empty_email" {
  command = plan

  variables {
    email = ""
  }

  expect_failures = [var.email]
}

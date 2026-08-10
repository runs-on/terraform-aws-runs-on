mock_provider "aws" {
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
  github_enterprise_pat  = "github_pat_invalid"
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

run "rejects_enterprise_pat_without_ghp_prefix" {
  command = plan

  expect_failures = [var.github_enterprise_pat]
}

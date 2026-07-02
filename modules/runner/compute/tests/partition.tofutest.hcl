mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.eu"
      partition  = "aws-eusc"
    }
  }

  mock_data "aws_service_principal" {
    defaults = {
      name = "ec2.amazonaws.eu"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      unique_id = "AROATESTSTACKROLEID"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws-eusc:iam::123456789012:instance-profile/test-stack-ec2-instance-profile"
    }
  }
}

variables {
  region                  = "eusc-de-east-1"
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
      bucket_arn  = "arn:aws-eusc:s3:::test-stack-cache"
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
      enabled                = true
      registry_url           = "123456789012.dkr.ecr.eusc-de-east-1.amazonaws.eu"
      docker_hub_transparent = false
      rules = {
        docker_hub = {
          ecr_repository_prefix      = "docker-hub"
          upstream_registry_url      = "registry-1.docker.io"
          upstream_repository_prefix = ""
        }
      }
    }
  }
}

run "runner_policies_use_current_partition" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.ec2_ssm.policy_arn == "arn:aws-eusc:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "SSM managed policy ARN should use the current AWS partition."
  }

  assert {
    condition     = jsondecode(aws_iam_role.ec2_instance.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.eu"
    error_message = "runner trust policy should use the partition-aware EC2 service principal."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.ec2_create_tags.policy).Statement[1].Resource == "arn:aws-eusc:ec2:eusc-de-east-1:123456789012:instance/*"
    error_message = "runner CreateTags policy should use the current AWS partition."
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.ec2_cloudwatch_logs.policy).Statement[0].Resource, "arn:aws-eusc:logs:eusc-de-east-1:123456789012:log-group:test-stack/ec2/instances:*")
    error_message = "runner log policy should use the current AWS partition."
  }

  assert {
    condition = contains(
      jsondecode(aws_iam_role_policy.ec2_ecr_pull_through_cache_access[0].policy).Statement[1].Resource,
      "arn:aws-eusc:ecr:eusc-de-east-1:123456789012:repository/docker-hub/*"
    )
    error_message = "runner ECR pull-through policy should use the current AWS partition."
  }
}

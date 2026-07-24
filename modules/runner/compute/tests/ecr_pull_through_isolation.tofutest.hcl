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
      enabled           = true
      registry_url      = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
      docker_hub_prefix = "docker-hub"
      rules = {
        docker_hub = {
          ecr_repository_prefix      = "docker-hub"
          upstream_registry_url      = "registry-1.docker.io"
          upstream_repository_prefix = ""
        }
        ghcr = {
          ecr_repository_prefix      = "ghcr"
          upstream_registry_url      = "ghcr.io"
          upstream_repository_prefix = ""
        }
      }
    }
  }
}

run "pull_through_access_stays_scoped_to_rule_prefixes" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.ec2_ecr_pull_through_cache_access[0].policy).Statement) == 2
    error_message = "Policy should have exactly the auth token and prefix-scoped statements."
  }

  assert {
    condition = contains(
      jsondecode(aws_iam_role_policy.ec2_ecr_pull_through_cache_access[0].policy).Statement[1].Resource,
      "arn:aws:ecr:us-east-1:123456789012:repository/docker-hub/*"
    )
    error_message = "Docker Hub rule should be scoped to its repository prefix."
  }

  assert {
    condition = contains(
      jsondecode(aws_iam_role_policy.ec2_ecr_pull_through_cache_access[0].policy).Statement[1].Resource,
      "arn:aws:ecr:us-east-1:123456789012:repository/ghcr/*"
    )
    error_message = "ghcr rule should be scoped to its repository prefix."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.ec2_ecr_pull_through_cache_access[0].policy, "repository/*")
    error_message = "No statement may grant access on repository/* (account-wide ECR access)."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.ec2_ecr_pull_through_cache_access[0].policy).Statement :
      !can(statement.Condition)
    ])
    error_message = "Prefix scoping needs no IAM conditions; none should be present."
  }
}

run "launch_template_exports_registry_and_docker_hub_prefix" {
  command = plan

  assert {
    condition     = strcontains(local.linux_user_data_vars.EphemeralRegistryEnvLine, "RUNS_ON_ECR_PULL_THROUGH_CACHE=\"123456789012.dkr.ecr.us-east-1.amazonaws.com\"")
    error_message = "Linux user data should export the pull-through registry host."
  }

  assert {
    condition     = strcontains(local.linux_user_data_vars.EphemeralRegistryEnvLine, "RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_PREFIX=\"docker-hub\"")
    error_message = "Linux user data should export the Docker Hub rule prefix for the runner-local mirror."
  }

}

run "no_docker_hub_rule_omits_prefix_env" {
  command = plan

  variables {
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
        enabled           = true
        registry_url      = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
        docker_hub_prefix = ""
        rules = {
          ghcr = {
            ecr_repository_prefix      = "ghcr"
            upstream_registry_url      = "ghcr.io"
            upstream_repository_prefix = ""
          }
        }
      }
    }
  }

  assert {
    condition     = !strcontains(local.linux_user_data_vars.EphemeralRegistryEnvLine, "RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_PREFIX")
    error_message = "Without a Docker Hub rule, the prefix env line should be omitted."
  }

  assert {
    condition     = strcontains(local.linux_user_data_vars.EphemeralRegistryEnvLine, "RUNS_ON_ECR_PULL_THROUGH_CACHE=\"123456789012.dkr.ecr.us-east-1.amazonaws.com\"")
    error_message = "The registry host env line should still be exported."
  }
}

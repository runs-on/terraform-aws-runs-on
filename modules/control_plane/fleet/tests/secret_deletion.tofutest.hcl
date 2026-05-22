mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-plan-role"
    }
  }
}

variables {
  region     = "us-east-1"
  account_id = "123456789012"
  stack_name = "test-plan"

  github = {
    app_id          = null
    app_private_key = null
    enterprise_pat  = "ghp_test"
    base_url        = "https://github.com"
    enterprise      = "test-enterprise"
    license_key     = "test-license"
  }

  catalog = {
    images = {
      ubuntu24-full-x64 = {
        ami      = "ami-12345678"
        platform = "linux"
        arch     = "x64"
      }
    }
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

  network = {
    vpc_id             = "vpc-12345678"
    private_mode       = "false"
    public_subnet_ids  = ["subnet-11111111"]
    private_subnet_ids = []
    security_group_ids = ["sg-11111111"]
  }

  extras = {
    cache = {
      bucket_id   = "test-cache"
      bucket_name = "test-cache"
      bucket_arn  = "arn:aws:s3:::test-cache"
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
  }

  compute = {
    runner_iam = {
      role_arn     = "arn:aws:iam::123456789012:role/test-runner"
      role_name    = "test-runner"
      role_id      = "AROA123456789"
      profile_arn  = "arn:aws:iam::123456789012:instance-profile/test-runner"
      profile_name = "test-runner"
    }
    runner_logs = {
      group_name          = "/aws/ec2/test-plan"
      group_arn           = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ec2/test-plan"
      resource_group_name = "test-plan-runners"
      resource_group_arn  = "arn:aws:resource-groups:us-east-1:123456789012:group/test-plan-runners"
    }
    launch_templates = {
      linux_default = {
        id             = "lt-11111111"
        latest_version = 1
      }
      linux_default_nested = {
        id             = "lt-22222222"
        latest_version = 1
      }
      windows_default = {
        id             = "lt-33333333"
        latest_version = 1
      }
      windows_default_nested = {
        id             = "lt-44444444"
        latest_version = 1
      }
      linux_private = {
        id             = "lt-55555555"
        latest_version = 1
      }
      linux_private_nested = {
        id             = "lt-66666666"
        latest_version = 1
      }
      windows_private = {
        id             = "lt-77777777"
        latest_version = 1
      }
      windows_private_nested = {
        id             = "lt-88888888"
        latest_version = 1
      }
    }
  }

  tags = {}

  runtime = {
    image              = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:test"
    size               = "small"
    capacity_provider  = "FARGATE"
    maintenance_mode   = false
    log_retention_days = 7
    extra_env_vars     = {}
  }

  integration_step_security_api_key = "step-security-secret"

  control_plane = {
    environment         = "test"
    private_mode        = "false"
    cost_allocation_tag = "stack"
    app_tag             = "dev"
    runner_custom_tags  = []
  }
}

run "fleet_config_secret_is_deleted_immediately" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.config.name == "/runs-on/test-plan/fleet-config"
    error_message = "Fleet config secret should use the shared /runs-on/<stack>/... namespace."
  }

  assert {
    condition     = aws_secretsmanager_secret.config.recovery_window_in_days == 0
    error_message = "Fleet config secret should be deleted immediately so dev stack names can be reused."
  }

  assert {
    condition     = nonsensitive(local.secret_payload.integrations.stepSecurityApiKey) == "step-security-secret"
    error_message = "Fleet config secret should include the StepSecurity integration key."
  }
}

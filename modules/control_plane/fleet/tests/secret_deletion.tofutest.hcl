mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.com"
      partition  = "aws"
    }
  }

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

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock"
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

  alerts = {
    email             = "alerts@example.com"
    slack_webhook_url = ""
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
    image                     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:test"
    size                      = "small"
    capacity_provider         = "FARGATE"
    maintenance_mode          = false
    log_retention_days        = 7
    otel_exporter_endpoint    = ""
    otel_exporter_headers     = ""
    otel_exporter_temporality = "cumulative"
    otel_logs_enabled         = true
    otel_traces_enabled       = true
    extra_env_vars            = {}
  }

  integration_step_security_api_key = "step-security-secret"

  control_plane = {
    environment          = "test"
    private_mode         = "false"
    cost_allocation_tag  = "stack"
    app_tag              = "dev"
    runner_custom_tags   = []
    spot_circuit_breaker = "3/20/45"
  }
}

run "otel_headers_add_ssm_parameter_and_execution_policy" {
  command = plan

  variables {
    runtime = {
      image                     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:test"
      size                      = "small"
      capacity_provider         = "FARGATE"
      maintenance_mode          = false
      log_retention_days        = 7
      otel_exporter_endpoint    = "https://collector.example.com:4318"
      otel_exporter_headers     = "x-signoz-ingestion-key=test"
      otel_exporter_temporality = "delta"
      otel_logs_enabled         = true
      otel_traces_enabled       = false
      extra_env_vars            = {}
    }
  }

  assert {
    condition     = length(aws_ssm_parameter.otel_exporter_headers) == 1 && aws_ssm_parameter.otel_exporter_headers[0].type == "SecureString"
    error_message = "OTEL headers should be stored as an SSM SecureString when configured."
  }

  assert {
    condition     = length(local.fleet_extra_execution_role_statements) == 1
    error_message = "OTEL headers should add an extra execution-role policy statement."
  }

  assert {
    condition     = local.fleet_extra_execution_role_statements[0].Action == ["ssm:GetParameters"]
    error_message = "OTEL execution policy should grant only ssm:GetParameters."
  }

  assert {
    condition     = local.fleet_extra_execution_role_statements[0].Resource == "arn:aws:ssm:us-east-1:123456789012:parameter/test-plan/secrets/otel-exporter-headers"
    error_message = "OTEL execution policy should be scoped to the headers parameter."
  }
}

run "without_otel_headers_skips_ssm_parameter_and_execution_policy" {
  command = plan

  assert {
    condition     = length(aws_ssm_parameter.otel_exporter_headers) == 0
    error_message = "OTEL headers parameter should be absent when no headers are configured."
  }

  assert {
    condition     = length(local.fleet_extra_execution_role_statements) == 0
    error_message = "Extra execution-role policy statements should be absent when no ECS secret is configured."
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

  assert {
    condition     = local.secret_payload.infra.alert_topic_arn == module.alerts.topic_arn
    error_message = "Fleet config secret should include the alert topic ARN."
  }

  assert {
    condition     = local.secret_payload.spot_circuit_breaker == "3/20/45"
    error_message = "Fleet config secret should carry the spot circuit breaker setting."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.config_materializer.name == "/runs-on/test-plan/lambda/fleet-config-materializer",
      aws_cloudwatch_log_group.job_diagnostics_resolver.name == "/runs-on/test-plan/lambda/job-diagnostics-resolver",
    ])
    error_message = "Fleet Lambda log groups should use the /runs-on/<stack>/lambda/<component> namespace."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.config_materializer.retention_in_days == 14,
      aws_cloudwatch_log_group.job_diagnostics_resolver.retention_in_days == 14,
      try(aws_cloudwatch_log_group.config_materializer.kms_key_id, null) == null,
      try(aws_cloudwatch_log_group.job_diagnostics_resolver.kms_key_id, null) == null,
    ])
    error_message = "Fleet Lambda log groups should use 14-day retention and default CloudWatch Logs encryption."
  }

  assert {
    condition = alltrue([
      aws_lambda_function.config_materializer.logging_config[0].log_group == aws_cloudwatch_log_group.config_materializer.name,
      aws_lambda_function.job_diagnostics_resolver.logging_config[0].log_group == aws_cloudwatch_log_group.job_diagnostics_resolver.name,
    ])
    error_message = "Fleet Lambda functions should write to their managed log groups."
  }
}

run "cache_isolation_disabled_keeps_broker_idle" {
  command = plan

  assert {
    condition     = aws_lambda_function.cache_credential_broker.function_name == "test-plan-cache-broker"
    error_message = "Cache credential broker Lambda should always be created."
  }

  assert {
    condition     = aws_iam_role.cache_credential_broker.name == "test-plan-cache-broker-role"
    error_message = "Cache credential broker role should always be created."
  }

  assert {
    condition     = local.secret_payload.infra.cache_credential_broker_function_name == ""
    error_message = "Fleet config should carry an empty broker function name so runners use direct cache access."
  }
}

run "runtime_secret_preserves_the_validated_catalog" {
  command = plan

  assert {
    condition     = jsonencode(local.secret_payload.images) == jsonencode(var.catalog.images) && jsonencode(local.secret_payload.runners) == jsonencode(var.catalog.runners) && jsonencode(local.secret_payload.fleets) == jsonencode(var.catalog.fleets)
    error_message = "Fleet runtime config must preserve the catalog after root-module validation."
  }
}

run "cache_isolation_enabled_deploys_broker" {
  command = plan

  variables {
    enable_cache_isolation = true
  }

  assert {
    condition     = aws_lambda_function.cache_credential_broker.function_name == "test-plan-cache-broker"
    error_message = "enable_cache_isolation should keep the cache credential broker Lambda available."
  }

  assert {
    condition     = local.secret_payload.infra.cache_credential_broker_function_name == "test-plan-cache-broker"
    error_message = "Fleet config should carry the broker function name so runners request brokered credentials."
  }
}

run "github_api_root_base_url_derives_normalized_broker_issuer" {
  command = plan

  variables {
    github = {
      app_id          = null
      app_private_key = null
      enterprise_pat  = "ghp_test"
      base_url        = "https://ghe.example.com/api/v3"
      enterprise      = "test-enterprise"
      license_key     = "test-license"
    }
  }

  assert {
    condition     = local.normalized_github_base_url == "https://ghe.example.com"
    error_message = "Fleet should strip a terminal /api/v3 from github_base_url before runtime URL derivation."
  }

  assert {
    condition     = nonsensitive(local.secret_payload.github_base_url) == "https://ghe.example.com"
    error_message = "Fleet runtime config should receive the normalized GitHub host root."
  }

  assert {
    condition     = aws_lambda_function.cache_credential_broker.environment[0].variables.GITHUB_ENTERPRISE_URL == "https://ghe.example.com"
    error_message = "Fleet broker should receive the normalized GHES host root."
  }

  assert {
    condition     = aws_lambda_function.cache_credential_broker.environment[0].variables.GITHUB_TOKEN_ISSUER == "https://ghe.example.com/_services/token"
    error_message = "Fleet broker issuer should match the control-plane JWKS issuer."
  }
}

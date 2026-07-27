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

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:mock"
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

  assert {
    condition     = !contains(keys(local.common_tags), "Environment")
    error_message = "Fleet must not synthesize the conventional Environment tag."
  }

  assert {
    condition     = local.fleet_diagnostic_settings.storage.ebs_encryption_mode == "unspecified"
    error_message = "Fleet should report omitted explicit EBS encryption as unspecified."
  }
}

run "telemetry_diagnostics_follow_extra_env_overrides" {
  command = plan

  variables {
    otel_exporter_endpoint    = "https://configured.example"
    otel_exporter_temporality = "cumulative"
    otel_logs_enabled         = true
    otel_traces_enabled       = true
    extra_env_vars = {
      OTEL_EXPORTER_OTLP_ENDPOINT    = ""
      OTEL_EXPORTER_OTLP_HEADERS     = "Authorization=private"
      OTEL_EXPORTER_OTLP_TEMPORALITY = "delta"
      OTEL_LOGS_ENABLED              = "off"
      OTEL_TRACES_ENABLED            = "0"
    }
  }

  assert {
    condition = (
      !local.fleet_diagnostic_settings.telemetry.exporter_configured &&
      local.fleet_diagnostic_settings.telemetry.headers_configured &&
      local.fleet_diagnostic_settings.telemetry.temporality == "delta" &&
      !local.fleet_diagnostic_settings.telemetry.logs_enabled &&
      !local.fleet_diagnostic_settings.telemetry.traces_enabled
    )
    error_message = "Fleet telemetry diagnostics should reflect the effective ECS environment after overrides."
  }
}

run "invalid_telemetry_headers_report_unconfigured" {
  command = plan

  variables {
    otel_exporter_headers = "Authorization"
    extra_env_vars = {
      OTEL_EXPORTER_OTLP_HEADERS = "=token, Empty= "
    }
  }

  assert {
    condition     = !local.fleet_diagnostic_settings.telemetry.headers_configured
    error_message = "Fleet header diagnostics should ignore entries the runtime OTLP parser discards."
  }
}

run "runner_tag_diagnostics_follow_runtime_filtering" {
  command = plan

  variables {
    runner_custom_tags = [" ", "runs-on-reserved=value"]
  }

  assert {
    condition     = !local.fleet_diagnostic_settings.runner.custom_tags_configured
    error_message = "Fleet runner tag diagnostics should ignore blank and reserved custom tags."
  }
}

run "runner_bare_key_tag_reports_configured" {
  command = plan

  variables {
    runner_custom_tags = ["missing-equals"]
  }

  assert {
    condition     = local.fleet_diagnostic_settings.runner.custom_tags_configured
    error_message = "Bare custom tag keys are valid and should be reported as configured."
  }
}

run "preserves_caller_supplied_environment_tag" {
  command = plan

  variables {
    tags = {
      Environment = "customer-value"
    }
  }

  assert {
    condition     = local.common_tags["Environment"] == "customer-value"
    error_message = "Fleet must preserve a caller-supplied Environment tag."
  }
}

run "multiple_transparent_docker_hub_rules_are_rejected" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      first = {
        ecr_repository_prefix = "docker-hub-one"
        upstream_registry_url = "registry-1.docker.io"
      }
      second = {
        ecr_repository_prefix = "docker-hub-two"
        upstream_registry_url = "registry-1.docker.io"
      }
    }
  }

  expect_failures = [var.ecr_pull_through_cache_rules]
}

run "exports_alerts_with_slack_webhook" {
  command = plan

  variables {
    alert_slack_webhook_url = "https://hooks.slack.com/services/example"
  }

  assert {
    condition     = output.alerts.slack_webhook_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:mock"
    error_message = "Fleet root alerts output should expose the non-secret Slack webhook Lambda ARN."
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

run "accepts_valid_runner_sticky_spec" {
  command = plan

  variables {
    runners = {
      small-x64 = {
        cpu    = 2
        ram    = 4
        family = ["c7"]
        image  = "ubuntu24-full-x64"
        sticky = "go-cache:gp3:750mbs:20gb:6000iops"
      }
    }
  }
}

run "rejects_invalid_runner_sticky_spec" {
  command = plan

  variables {
    runners = {
      small-x64 = {
        cpu    = 2
        ram    = 4
        family = ["c7"]
        image  = "ubuntu24-full-x64"
        sticky = "not-a-size"
      }
    }
  }

  expect_failures = [terraform_data.validate_runner_sticky_specs]
}

run "rejects_non_string_runner_sticky_spec" {
  command = plan

  variables {
    runners = {
      small-x64 = {
        cpu    = 2
        ram    = 4
        family = ["c7"]
        image  = "ubuntu24-full-x64"
        sticky = ["20gb"]
      }
    }
  }

  expect_failures = [terraform_data.validate_runner_sticky_specs]
}

run "private_only_allows_omitted_public_subnets" {
  command = plan

  variables {
    private_mode       = "only"
    private_subnet_ids = ["subnet-22222222"]
  }

  assert {
    condition     = output.workflow_contract.label == "runs-on/fleet=<fleet-name>/env=test"
    error_message = "private_mode=only should plan without public subnets."
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

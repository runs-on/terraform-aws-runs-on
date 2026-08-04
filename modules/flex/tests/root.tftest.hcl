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

  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.com"
      partition  = "aws"
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

  mock_resource "aws_secretsmanager_secret_version" {
    defaults = {
      version_id = "mock-version"
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
    condition     = strcontains(output.stack.getting_started, "WARNING: Custom environment name detected!")
    error_message = "custom environment names should explain the routing label without implying a deployment tier."
  }

  assert {
    condition     = !strcontains(output.stack.getting_started, "Non-production environment detected!")
    error_message = "custom environment names should not be described as non-production environments."
  }

  assert {
    condition     = output.platform.optional_features.efs.enabled == false && output.platform.optional_features.ecr.enabled == false
    error_message = "baseline optional features should be disabled."
  }

  assert {
    condition     = !contains(keys(local.common_tags), "Environment")
    error_message = "Flex must not synthesize the conventional Environment tag."
  }

  assert {
    condition     = local.flex_diagnostic_settings.runner.config_auto_extends_enabled
    error_message = "The default auto-extension repository should be reported as enabled."
  }

  assert {
    condition     = local.flex_diagnostic_settings.storage.ebs_encryption_mode == "unspecified"
    error_message = "Omitted explicit EBS encryption should be reported as unspecified."
  }
}

run "dot_auto_extends_sentinel_reports_disabled" {
  command = plan

  variables {
    runner_config_auto_extends_from = "."
  }

  assert {
    condition     = !local.flex_diagnostic_settings.runner.config_auto_extends_enabled
    error_message = "The runtime's dot sentinel should be reported as auto-extension disabled."
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
      OTEL_LOGS_ENABLED              = "false"
      OTEL_TRACES_ENABLED            = "no"
      RUNS_ON_LOGGER_LEVEL           = "debug"
    }
  }

  assert {
    condition = (
      !local.flex_diagnostic_settings.telemetry.exporter_configured &&
      local.flex_diagnostic_settings.telemetry.headers_configured &&
      local.flex_diagnostic_settings.telemetry.temporality == "delta" &&
      !local.flex_diagnostic_settings.telemetry.logs_enabled &&
      !local.flex_diagnostic_settings.telemetry.traces_enabled &&
      local.flex_diagnostic_settings.telemetry.logger_level == "debug"
    )
    error_message = "Telemetry diagnostics should reflect the effective ECS environment after overrides."
  }
}

run "logger_diagnostics_follow_runtime_whitespace_fallback" {
  command = plan

  variables {
    extra_env_vars = {
      RUNS_ON_LOGGER_LEVEL = " debug "
    }
  }

  assert {
    condition     = local.flex_diagnostic_settings.telemetry.logger_level == "info"
    error_message = "Logger diagnostics should preserve whitespace and match the runtime's exact-value fallback."
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
    condition     = !local.flex_diagnostic_settings.telemetry.headers_configured
    error_message = "Header diagnostics should ignore entries the runtime OTLP parser discards."
  }
}

run "runner_tag_diagnostics_follow_runtime_filtering" {
  command = plan

  variables {
    runner_custom_tags = [" ", "runs-on-reserved=value"]
  }

  assert {
    condition     = !local.flex_diagnostic_settings.runner.custom_tags_configured
    error_message = "Runner tag diagnostics should ignore blank and reserved custom tags."
  }
}

run "runner_bare_key_tag_reports_configured" {
  command = plan

  variables {
    runner_custom_tags = ["missing-equals"]
  }

  assert {
    condition     = local.flex_diagnostic_settings.runner.custom_tags_configured
    error_message = "Bare custom tag keys are valid and should be reported as configured."
  }
}

run "aws_managed_ebs_alias_arn_is_identified" {
  command = plan

  variables {
    ebs_encryption_key_id = "arn:aws:kms:us-east-1:123456789012:alias/aws/ebs"
  }

  assert {
    condition     = local.flex_diagnostic_settings.storage.ebs_encryption_mode == "aws-managed"
    error_message = "The AWS-managed EBS alias ARN should be identified without exposing the ARN."
  }
}

run "opaque_ebs_key_uses_neutral_mode" {
  command = plan

  variables {
    ebs_encryption_key_id = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = local.flex_diagnostic_settings.storage.ebs_encryption_mode == "explicit"
    error_message = "Opaque key ARNs should not be attributed to an ownership class."
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
    error_message = "Flex must preserve a caller-supplied Environment tag."
  }
}

run "exports_alerts_with_slack_webhook" {
  command = plan

  variables {
    alert_slack_webhook_url = "https://hooks.slack.com/services/example"
  }

  assert {
    condition     = output.alerts.slack_webhook_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:mock"
    error_message = "Flex root alerts output should expose the non-secret Slack webhook Lambda ARN."
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

run "ecr_pull_through_cache_docker_hub_prefix" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      docker_hub = {
        ecr_repository_prefix = "docker-hub"
        upstream_registry_url = "registry-1.docker.io"
      }
    }
  }

  assert {
    condition     = output.platform.optional_features.pull_through_cache.enabled == true
    error_message = "ECR pull-through cache should be enabled when rules are configured."
  }

  assert {
    condition     = output.platform.optional_features.pull_through_cache.registry_url == "123456789012.dkr.ecr.us-east-1.amazonaws.com"
    error_message = "ECR pull-through cache registry URL should be derived from account and region."
  }

  assert {
    condition     = output.platform.optional_features.pull_through_cache.docker_hub_prefix == "docker-hub"
    error_message = "The Docker Hub rule prefix should be exported for the runner-local registry mirror."
  }
}

run "ecr_pull_through_cache_root_prefix_is_rejected" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      docker_hub = {
        ecr_repository_prefix = "ROOT"
        upstream_registry_url = "registry-1.docker.io"
      }
    }
  }

  expect_failures = [var.ecr_pull_through_cache_rules]
}

run "ecr_pull_through_cache_multiple_providers" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      ghcr = {
        ecr_repository_prefix = "ghcr"
        upstream_registry_url = "ghcr.io"
      }
      quay = {
        ecr_repository_prefix = "quay"
        upstream_registry_url = "quay.io"
      }
    }
  }

  assert {
    condition     = output.platform.optional_features.pull_through_cache.enabled == true
    error_message = "ECR pull-through cache should be enabled when referenced rules are configured."
  }

  assert {
    condition     = output.platform.optional_features.pull_through_cache.docker_hub_prefix == ""
    error_message = "Non-Docker-Hub rules should not export a Docker Hub mirror prefix."
  }
}

run "ecr_pull_through_cache_accepts_official_rule_objects" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      docker_hub = {
        ecr_repository_prefix      = "docker-hub"
        upstream_registry_url      = "registry-1.docker.io"
        upstream_repository_prefix = ""
        registry_id                = "123456789012"
        credential_arn             = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ecr-pullthroughcache/docker-hub"
        id                         = "docker-hub"
      }
    }
  }

  assert {
    condition     = output.platform.optional_features.pull_through_cache.docker_hub_prefix == "docker-hub"
    error_message = "Official rule resource/data source objects should be accepted and normalized."
  }
}

run "ecr_pull_through_cache_empty_rule_reference_is_rejected" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      docker_hub = {
        ecr_repository_prefix = "docker-hub"
        upstream_registry_url = ""
      }
    }
  }

  expect_failures = [var.ecr_pull_through_cache_rules]
}

run "ecr_pull_through_cache_duplicate_prefix_is_rejected" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      first = {
        ecr_repository_prefix = "docker-hub"
        upstream_registry_url = "registry-1.docker.io"
      }
      second = {
        ecr_repository_prefix = "docker-hub"
        upstream_registry_url = "registry-1.docker.io"
      }
    }
  }

  expect_failures = [var.ecr_pull_through_cache_rules]
}

run "ecr_pull_through_cache_multiple_transparent_docker_hub_rules_are_rejected" {
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

run "ecr_pull_through_cache_allows_prefixed_and_transparent_docker_hub_rules" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = {
      transparent = {
        ecr_repository_prefix = "docker-hub"
        upstream_registry_url = "registry-1.docker.io"
      }
      upstream_prefixed = {
        ecr_repository_prefix      = "docker-hub-library"
        upstream_registry_url      = "registry-1.docker.io"
        upstream_repository_prefix = "library"
      }
    }
  }

  assert {
    condition     = output.platform.optional_features.pull_through_cache.docker_hub_prefix == "docker-hub"
    error_message = "Only the unprefixed Docker Hub rule should configure transparent mirroring."
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

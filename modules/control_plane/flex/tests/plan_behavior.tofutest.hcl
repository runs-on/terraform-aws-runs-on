mock_provider "aws" {
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:123456789012:rule/mock"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-east-1:123456789012:table/mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:123456789012:function:mock"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:mock/invocations"
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
  region              = "us-east-1"
  account_id          = "123456789012"
  stack_name          = "test-plan"
  environment         = "test"
  cost_allocation_tag = "runs-on-stack-name"
  license_key         = "test-license"

  network = {
    vpc_id             = "vpc-12345678"
    private_mode       = "false"
    public_subnet_ids  = ["subnet-public-a"]
    private_subnet_ids = ["subnet-private-a"]
    security_group_ids = ["sg-runners"]
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
    pull_through_cache = {
      enabled                = false
      registry_url           = ""
      docker_hub_transparent = false
      rules                  = {}
    }
  }

  compute = {
    runner_iam = {
      role_arn     = "arn:aws:iam::123456789012:role/test-runner"
      role_name    = "test-runner"
      role_id      = "test-runner-id"
      profile_arn  = "arn:aws:iam::123456789012:instance-profile/test-runner"
      profile_name = "test-runner"
    }
    runner_logs = {
      group_name          = "/aws/ec2/test-plan/runners"
      group_arn           = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ec2/test-plan/runners"
      resource_group_name = "test-plan-runners"
      resource_group_arn  = "arn:aws:resource-groups:us-east-1:123456789012:group/test-plan-runners"
    }
    launch_templates = {
      linux_default = {
        id             = "lt-linux-default"
        latest_version = 1
      }
      linux_default_nested = {
        id             = "lt-linux-default-nested"
        latest_version = 1
      }
      windows_default = {
        id             = "lt-windows-default"
        latest_version = 1
      }
      windows_default_nested = {
        id             = "lt-windows-default-nested"
        latest_version = 1
      }
      linux_private = {
        id             = "lt-linux-private"
        latest_version = 1
      }
      linux_private_nested = {
        id             = "lt-linux-private-nested"
        latest_version = 1
      }
      windows_private = {
        id             = "lt-windows-private"
        latest_version = 1
      }
      windows_private_nested = {
        id             = "lt-windows-private-nested"
        latest_version = 1
      }
    }
  }

  github = {
    organization   = "runs-on"
    enterprise_url = ""
    api_strategy   = "github_app"
    apps           = null
  }

  runner = {
    ssh_allowed              = false
    ebs_encryption_key_id    = ""
    max_runtime              = 7200
    config_auto_extends_from = ""
    custom_tags              = []
  }

  alerts = {
    email             = "alerts@example.com"
    slack_webhook_url = ""
  }

  runtime = {
    image                     = "public.ecr.aws/runs-on/flexd:test"
    tag                       = "test"
    maintenance_mode          = false
    size                      = "small"
    capacity_provider         = "FARGATE"
    force_new_deployment      = false
    private_mode              = "false"
    ecr_repository_url        = ""
    custom_policy_arn         = ""
    otel_exporter_endpoint    = ""
    otel_exporter_headers     = ""
    otel_exporter_temporality = "cumulative"
    otel_logs_enabled         = false
    otel_traces_enabled       = false
    logger_level              = "info"
    extra_env_vars            = {}
  }

  operations = {
    app_budget_daily_usd              = 0
    enable_cost_reports               = false
    spot_circuit_breaker              = ""
    integration_step_security_api_key = ""
    enable_admin_routes               = true
    enable_waf                        = false
    public_ingress_web_acl_arn        = ""
  }

  tags = {}
}

run "zero_budget_skips_budget_resources" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.app_daily_budget) == 0
    error_message = "Daily budget should be absent when app_budget_daily_usd is 0."
  }

}

run "positive_budget_creates_budget_resources" {
  command = plan

  variables {
    operations = {
      app_budget_daily_usd              = 10
      enable_cost_reports               = false
      spot_circuit_breaker              = ""
      integration_step_security_api_key = ""
      enable_admin_routes               = true
      enable_waf                        = false
      public_ingress_web_acl_arn        = ""
    }
  }

  assert {
    condition     = length(aws_budgets_budget.app_daily_budget) == 1
    error_message = "Daily budget should be created when app_budget_daily_usd is greater than 0."
  }
}

run "managed_waf_creates_sync_resources" {
  command = plan

  variables {
    operations = {
      app_budget_daily_usd              = 0
      enable_cost_reports               = false
      spot_circuit_breaker              = ""
      integration_step_security_api_key = ""
      enable_admin_routes               = true
      enable_waf                        = true
      public_ingress_web_acl_arn        = ""
    }
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1
    error_message = "Managed WAF should create a Web ACL."
  }

  assert {
    condition     = length(aws_lambda_function.github_waf_sync) == 1 && length(aws_lambda_invocation.github_waf_sync_seed) == 1
    error_message = "Managed WAF should create the GitHub WAF sync Lambda and seed invocation."
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowed_ips_ipv4) == 1 && length(aws_wafv2_ip_set.allowed_ips_ipv6) == 1
    error_message = "Managed WAF should create IPv4 and IPv6 IP sets."
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowed_ips_ipv4[0].addresses) == 0 && length(aws_wafv2_ip_set.allowed_ips_ipv6[0].addresses) == 0
    error_message = "Managed WAF IP sets should start empty so the sync Lambda owns addresses."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.github_waf_sync_lambda[0].name == "/runs-on/test-plan/lambda/github-waf-sync" &&
      aws_cloudwatch_log_group.github_waf_sync_lambda[0].retention_in_days == 14 &&
      try(aws_cloudwatch_log_group.github_waf_sync_lambda[0].kms_key_id, null) == null &&
      aws_lambda_function.github_waf_sync[0].logging_config[0].log_group == aws_cloudwatch_log_group.github_waf_sync_lambda[0].name
    )
    error_message = "Managed WAF sync Lambda should write to its stack-scoped log group."
  }
}

run "default_dashboard_can_be_disabled" {
  command = plan

  variables {
    operations = {
      app_budget_daily_usd              = 0
      enable_default_dashboard          = false
      enable_cost_reports               = false
      spot_circuit_breaker              = ""
      integration_step_security_api_key = ""
      enable_admin_routes               = true
      enable_waf                        = false
      public_ingress_web_acl_arn        = ""
    }
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.runs_on) == 0
    error_message = "Default dashboard should be absent when enable_default_dashboard is false."
  }
}

run "user_managed_waf_skips_sync_resources" {
  command = plan

  variables {
    operations = {
      app_budget_daily_usd              = 0
      enable_cost_reports               = false
      spot_circuit_breaker              = ""
      integration_step_security_api_key = ""
      enable_admin_routes               = true
      enable_waf                        = true
      public_ingress_web_acl_arn        = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/custom/abcd1234"
    }
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 0
    error_message = "User-managed WAF should not create a managed Web ACL."
  }

  assert {
    condition     = length(aws_lambda_function.github_waf_sync) == 0 && length(aws_lambda_invocation.github_waf_sync_seed) == 0
    error_message = "User-managed WAF should not create GitHub WAF sync resources."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.public_ingress) == 1 && aws_wafv2_web_acl_association.public_ingress[0].web_acl_arn == "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/custom/abcd1234"
    error_message = "User-managed WAF should associate the provided Web ACL ARN."
  }
}

run "admin_routes_disabled_skips_setup_resources" {
  command = plan

  variables {
    operations = {
      app_budget_daily_usd              = 0
      enable_cost_reports               = false
      spot_circuit_breaker              = ""
      integration_step_security_api_key = ""
      enable_admin_routes               = false
      enable_waf                        = false
      public_ingress_web_acl_arn        = ""
    }
  }

  assert {
    condition     = length(aws_lambda_function.github_apps_setup) == 0
    error_message = "Admin setup Lambda should be absent when admin routes are disabled."
  }

  assert {
    condition     = length(aws_api_gateway_resource.setup) == 0 && length(aws_api_gateway_resource.readyz) == 0
    error_message = "Admin API routes should be absent when admin routes are disabled."
  }
}

run "lambda_log_groups_use_stack_namespace" {
  command = plan

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.public_ingress_lambda.name == "/runs-on/test-plan/lambda/public-ingress",
      aws_cloudwatch_log_group.github_apps_setup_lambda[0].name == "/runs-on/test-plan/lambda/github-apps-setup",
      aws_cloudwatch_log_group.github_runner_cache_refresh_lambda.name == "/runs-on/test-plan/lambda/github-runner-cache-refresh",
      aws_cloudwatch_log_group.stack_config_materializer.name == "/runs-on/test-plan/lambda/stack-config-materializer",
      aws_cloudwatch_log_group.job_diagnostics_resolver.name == "/runs-on/test-plan/lambda/job-diagnostics-resolver",
    ])
    error_message = "Flex Lambda log groups should use the /runs-on/<stack>/lambda/<component> namespace."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.public_ingress_lambda.retention_in_days == 14,
      aws_cloudwatch_log_group.github_apps_setup_lambda[0].retention_in_days == 14,
      aws_cloudwatch_log_group.github_runner_cache_refresh_lambda.retention_in_days == 14,
      aws_cloudwatch_log_group.stack_config_materializer.retention_in_days == 14,
      aws_cloudwatch_log_group.job_diagnostics_resolver.retention_in_days == 14,
    ])
    error_message = "Flex Lambda log groups should retain logs for 14 days."
  }

  assert {
    condition = alltrue([
      try(aws_cloudwatch_log_group.public_ingress_lambda.kms_key_id, null) == null,
      try(aws_cloudwatch_log_group.github_apps_setup_lambda[0].kms_key_id, null) == null,
      try(aws_cloudwatch_log_group.github_runner_cache_refresh_lambda.kms_key_id, null) == null,
      try(aws_cloudwatch_log_group.stack_config_materializer.kms_key_id, null) == null,
      try(aws_cloudwatch_log_group.job_diagnostics_resolver.kms_key_id, null) == null,
    ])
    error_message = "Flex Lambda log groups should rely on CloudWatch Logs default encryption."
  }

  assert {
    condition = alltrue([
      aws_lambda_function.public_ingress.logging_config[0].log_group == aws_cloudwatch_log_group.public_ingress_lambda.name,
      aws_lambda_function.github_apps_setup[0].logging_config[0].log_group == aws_cloudwatch_log_group.github_apps_setup_lambda[0].name,
      aws_lambda_function.github_runner_cache_refresh.logging_config[0].log_group == aws_cloudwatch_log_group.github_runner_cache_refresh_lambda.name,
      aws_lambda_function.stack_config_materializer.logging_config[0].log_group == aws_cloudwatch_log_group.stack_config_materializer.name,
      aws_lambda_function.job_diagnostics_resolver.logging_config[0].log_group == aws_cloudwatch_log_group.job_diagnostics_resolver.name,
    ])
    error_message = "Flex Lambda functions should write to their managed log groups."
  }
}

run "github_apps_setup_spot_service_role_permissions_are_scoped" {
  command = plan

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.github_apps_setup[0].policy).Statement :
      statement.Action == ["iam:GetRole"] &&
      statement.Resource == "arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot" &&
      !can(statement.Condition)
    ])
    error_message = "GitHub Apps setup Lambda should only read the EC2 Spot service-linked role."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.github_apps_setup[0].policy).Statement :
      statement.Action == ["iam:CreateServiceLinkedRole"] &&
      statement.Resource == "arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot" &&
      try(statement.Condition.StringEquals["iam:AWSServiceName"], "") == "spot.amazonaws.com"
    ])
    error_message = "GitHub Apps setup Lambda should only create the EC2 Spot service-linked role."
  }
}

run "worker_policy_scopes_stack_state_resources" {
  command = plan

  assert {
    condition = anytrue([
      for statement in local.flex_control_plane_extra_policy_statements :
      statement.Action == [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
      ] &&
      statement.Resource == aws_ssm_parameter.license_status.arn
    ])
    error_message = "Worker SSM access should be scoped to the license-status parameter."
  }

  assert {
    condition = alltrue(flatten([
      for statement in local.flex_control_plane_extra_policy_statements : [
        for action in try(statement.Action, []) :
        !startswith(action, "ssm:Delete")
      ]
    ]))
    error_message = "Worker SSM access should not include parameter delete permissions."
  }

  assert {
    condition = anytrue([
      for statement in local.flex_control_plane_extra_policy_statements :
      contains(try(statement.Action, []), "sqs:ReceiveMessage") &&
      try(length(statement.Resource), 0) == 3 &&
      try(contains(statement.Resource, aws_sqs_queue.webhooks.arn), false) &&
      try(contains(statement.Resource, aws_sqs_queue.system.arn), false) &&
      try(contains(statement.Resource, aws_sqs_queue.events.arn), false)
    ])
    error_message = "Worker SQS access should be limited to active queues, not DLQs."
  }

  assert {
    condition = anytrue([
      for statement in local.flex_control_plane_extra_policy_statements :
      contains(try(statement.Action, []), "dynamodb:Query") &&
      try(contains(statement.Resource, "${aws_dynamodb_table.workflow_jobs.arn}/index/reconcile-index"), false) &&
      try(contains(statement.Resource, "${aws_dynamodb_table.workflow_jobs.arn}/index/pending-work-index"), false) &&
      try(contains(statement.Resource, "${aws_dynamodb_table.workflow_jobs.arn}/index/daily-activity-index"), false) &&
      !try(contains(statement.Resource, "${aws_dynamodb_table.workflow_jobs.arn}/index/*"), false)
    ])
    error_message = "Worker DynamoDB access should enumerate known workflow-job indexes."
  }
}

run "otel_headers_add_ssm_parameter_and_execution_policy" {
  command = plan

  variables {
    runtime = {
      image                     = "public.ecr.aws/runs-on/flexd:test"
      tag                       = "test"
      maintenance_mode          = false
      size                      = "small"
      capacity_provider         = "FARGATE"
      force_new_deployment      = false
      private_mode              = "false"
      ecr_repository_url        = ""
      custom_policy_arn         = ""
      otel_exporter_endpoint    = ""
      otel_exporter_headers     = "x-signoz-ingestion-key=test"
      otel_exporter_temporality = "cumulative"
      otel_logs_enabled         = false
      otel_traces_enabled       = false
      logger_level              = "info"
      extra_env_vars            = {}
    }
  }

  assert {
    condition     = length(aws_ssm_parameter.otel_exporter_headers) == 1 && aws_ssm_parameter.otel_exporter_headers[0].type == "SecureString"
    error_message = "OTEL headers should be stored as an SSM SecureString when configured."
  }

  assert {
    condition     = length(local.flex_control_plane_extra_execution_role_statements) == 1
    error_message = "OTEL headers should add an extra execution-role policy statement."
  }

  assert {
    condition     = local.flex_control_plane_extra_execution_role_statements[0].Action == ["ssm:GetParameters"]
    error_message = "OTEL execution policy should grant only ssm:GetParameters."
  }

  assert {
    condition     = local.flex_control_plane_extra_execution_role_statements[0].Resource == "arn:aws:ssm:us-east-1:123456789012:parameter/test-plan/secrets/otel-exporter-headers"
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
    condition     = length(local.flex_control_plane_extra_execution_role_statements) == 0
    error_message = "Extra execution-role policy statements should be absent when no ECS secret is configured."
  }
}

run "github_runner_cache_refresh_seed_uses_cache_bucket" {
  command = plan

  assert {
    condition     = aws_lambda_invocation.github_runner_cache_refresh_seed.function_name == aws_lambda_function.github_runner_cache_refresh.function_name
    error_message = "GitHub runner cache refresh seed invocation should be planned."
  }

  assert {
    condition     = jsondecode(aws_lambda_invocation.github_runner_cache_refresh_seed.input).input.bucket == "test-cache"
    error_message = "GitHub runner cache refresh seed should use the configured cache bucket name."
  }
}

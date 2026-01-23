# modules/core/main.tf
# Core module orchestration for RunsOn - App Runner, SQS, DynamoDB, SNS, EventBridge

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Local variables
locals {
  common_tags = var.tags

  # Non-sensitive environment variables for App Runner (before filtering)
  # Sensitive vars (license_key, server_password, etc.) are in sensitive_env_secrets
  all_env_vars = {
    RUNS_ON_AWS_ACCOUNT_ID                   = var.account_id
    RUNS_ON_ENV                              = var.environment
    RUNS_ON_COST_ALLOCATION_TAG              = var.cost_allocation_tag
    RUNS_ON_STACK_NAME                       = var.stack_name
    RUNS_ON_LOCKS_TABLE                      = aws_dynamodb_table.locks.name
    RUNS_ON_WORKFLOW_JOBS_TABLE              = aws_dynamodb_table.workflow_jobs.name
    RUNS_ON_NETWORKING_STACK                 = "external"
    RUNS_ON_GITHUB_ORGANIZATION              = var.github_organization
    RUNS_ON_APP_TAG                          = var.app_tag
    RUNS_ON_BOOTSTRAP_TAG                    = var.bootstrap_tag
    RUNS_ON_RUNNER_CUSTOM_TAGS               = join(",", var.runner_custom_tags)
    RUNS_ON_BUCKET_CONFIG                    = var.config_bucket_name
    RUNS_ON_BUCKET_CACHE                     = var.cache_bucket_name
    RUNS_ON_VPC_ID                           = var.vpc_id
    RUNS_ON_SECURITY_GROUP_ID                = join(",", var.security_group_ids)
    RUNS_ON_INSTANCE_PROFILE_ARN             = var.ec2_instance_profile_arn
    RUNS_ON_INSTANCE_ROLE_NAME               = var.ec2_instance_role_name
    RUNS_ON_TOPIC_ARN                        = aws_sns_topic.alerts.arn
    RUNS_ON_REGION                           = var.region
    RUNS_ON_SSH_ALLOWED                      = var.ssh_allowed ? "true" : "false"
    RUNS_ON_APP_EC2_QUEUE_SIZE               = tostring(var.ec2_queue_size)
    RUNS_ON_EBS_ENCRYPTION_KEY               = var.ebs_encryption_key_id
    RUNS_ON_APP_GITHUB_API_STRATEGY          = var.github_api_strategy
    RUNS_ON_PUBLIC_SUBNET_IDS                = join(",", var.public_subnet_ids)
    RUNS_ON_PRIVATE_SUBNET_IDS               = join(",", var.private_subnet_ids)
    RUNS_ON_PRIVATE                          = var.private_mode
    RUNS_ON_DEFAULT_ADMINS                   = var.default_admins
    RUNS_ON_RUNNER_MAX_RUNTIME               = tostring(var.runner_max_runtime)
    RUNS_ON_RUNNER_CONFIG_AUTO_EXTENDS_FROM  = var.runner_config_auto_extends_from
    RUNS_ON_LAUNCH_TEMPLATE_LINUX_DEFAULT    = var.launch_template_linux_default_id
    RUNS_ON_LAUNCH_TEMPLATE_WINDOWS_DEFAULT  = var.launch_template_windows_default_id
    RUNS_ON_LAUNCH_TEMPLATE_LINUX_PRIVATE    = var.launch_template_linux_private_id
    RUNS_ON_LAUNCH_TEMPLATE_WINDOWS_PRIVATE  = var.launch_template_windows_private_id
    RUNS_ON_RUNNER_DEFAULT_DISK_SIZE         = tostring(var.runner_default_disk_size)
    RUNS_ON_RUNNER_DEFAULT_VOLUME_THROUGHPUT = tostring(var.runner_default_volume_throughput)
    RUNS_ON_RUNNER_LARGE_DISK_SIZE           = tostring(var.runner_large_disk_size)
    RUNS_ON_RUNNER_LARGE_VOLUME_THROUGHPUT   = tostring(var.runner_large_volume_throughput)
    RUNS_ON_QUEUE                            = aws_sqs_queue.main.name
    RUNS_ON_QUEUE_POOL                       = aws_sqs_queue.pool.name
    RUNS_ON_QUEUE_HOUSEKEEPING               = aws_sqs_queue.housekeeping.name
    RUNS_ON_QUEUE_TERMINATION                = aws_sqs_queue.termination.name
    RUNS_ON_QUEUE_EVENTS                     = aws_sqs_queue.events.name
    RUNS_ON_QUEUE_JOBS                       = aws_sqs_queue.jobs.name
    RUNS_ON_QUEUE_GITHUB                     = aws_sqs_queue.github.name
    RUNS_ON_COST_REPORTS_ENABLED             = var.enable_cost_reports ? "true" : "false"
    RUNS_ON_SPOT_CIRCUIT_BREAKER             = var.spot_circuit_breaker
    RUNS_ON_GITHUB_ENTERPRISE_URL            = var.github_enterprise_url
    OTEL_EXPORTER_OTLP_ENDPOINT              = var.otel_exporter_endpoint
    RUNS_ON_LOGGER_LEVEL                     = var.logger_level
  }

  # AWS App Runner doesn't store empty env vars, causing drift on every plan
  base_env_vars = { for k, v in local.all_env_vars : k => v if v != "" }

  # App Runner log group name for CloudWatch dashboard queries
  apprunner_log_group_name = "/aws/apprunner/${aws_apprunner_service.this.service_name}/${aws_apprunner_service.this.service_id}/application"

  # Sensitive environment variables stored in SSM Parameter Store
  # App Runner fetches these at runtime via runtime_environment_secrets
  sensitive_env_secrets = merge(
    var.license_key != "" ? {
      RUNS_ON_LICENSE_KEY = aws_ssm_parameter.license_key[0].arn
    } : {},
    var.server_password != "" ? {
      RUNS_ON_SERVER_PASSWORD = aws_ssm_parameter.server_password[0].arn
    } : {},
    var.integration_step_security_api_key != "" ? {
      RUNS_ON_INTEGRATION_STEP_SECURITY_API_KEY = aws_ssm_parameter.integration_step_security_api_key[0].arn
    } : {},
    var.otel_exporter_headers != "" ? {
      OTEL_EXPORTER_OTLP_HEADERS = aws_ssm_parameter.otel_exporter_headers[0].arn
    } : {}
  )
}

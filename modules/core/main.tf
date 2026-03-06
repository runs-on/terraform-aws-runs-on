# modules/core/main.tf
# Core module orchestration for RunsOn - App Runner, SQS, DynamoDB, SNS, EventBridge

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}

# Local variables
locals {
  common_tags = var.tags

  app_image_digest       = try(lower(regex("^.*@sha256:([a-fA-F0-9]+)$", var.app_image)[0]), substr(sha1(var.app_image), 0, 12))
  stack_config_secret_id = "/runs-on/${var.stack_name}/config/${local.app_image_digest}"

  # Keep these as direct env vars because they are consumed before stack config is loaded.
  all_env_vars = merge(
    {
      RUNS_ON_ENV                    = var.environment
      RUNS_ON_STACK_NAME             = var.stack_name
      RUNS_ON_APP_TAG                = var.app_tag
      RUNS_ON_MAINTENANCE_MODE       = tostring(var.maintenance_mode)
      OTEL_EXPORTER_OTLP_ENDPOINT    = var.otel_exporter_endpoint
      OTEL_EXPORTER_OTLP_TEMPORALITY = var.otel_exporter_temporality
      RUNS_ON_LOGGER_LEVEL           = var.logger_level
    },
    var.extra_env_vars,
  )

  # AWS App Runner doesn't store empty env vars, causing drift on every plan
  base_env_vars = { for k, v in local.all_env_vars : k => v if v != "" }

  # Most stack configuration is now passed as RUNS_ON_STACK_CONFIG_JSON.
  stack_config_json = jsonencode({
    AwsAccountId                  = var.account_id
    Private                       = var.private_mode
    GithubOrganization            = var.github_organization
    Region                        = var.region
    LicenseKey                    = var.license_key
    BucketConfig                  = var.config_bucket_name
    BucketCache                   = var.cache_bucket_name
    InstanceRoleName              = var.ec2_instance_role_name
    SshAllowed                    = var.ssh_allowed ? "true" : "false"
    LaunchTemplateLinuxDefault    = var.launch_template_linux_default_id
    LaunchTemplateWindowsDefault  = var.launch_template_windows_default_id
    LaunchTemplateLinuxPrivate    = var.launch_template_linux_private_id
    LaunchTemplateWindowsPrivate  = var.launch_template_windows_private_id
    PublicSubnetIds               = var.public_subnet_ids
    PrivateSubnetIds              = var.private_subnet_ids
    DefaultAdmins                 = var.default_admins
    TopicArn                      = aws_sns_topic.alerts.arn
    RunnerDefaultDiskSize         = var.runner_default_disk_size
    RunnerDefaultVolumeThroughput = var.runner_default_volume_throughput
    RunnerLargeDiskSize           = var.runner_large_disk_size
    RunnerLargeVolumeThroughput   = var.runner_large_volume_throughput
    RunnerCustomTags              = join(",", var.runner_custom_tags)
    RunnerMaxRuntime              = var.runner_max_runtime
    RunnerConfigAutoExtendsFrom   = var.runner_config_auto_extends_from
    EbsEncryptionKey              = var.ebs_encryption_key_id
    AppGithubApiStrategy          = var.github_api_strategy
    AppTag                        = var.app_tag
    StackName                     = var.stack_name
    AppEc2QueueSize               = var.ec2_queue_size
    Queue                         = aws_sqs_queue.main.name
    QueueJobs                     = aws_sqs_queue.jobs.name
    QueueGithub                   = aws_sqs_queue.github.name
    QueuePool                     = aws_sqs_queue.pool.name
    QueueHousekeeping             = aws_sqs_queue.housekeeping.name
    QueueTermination              = aws_sqs_queue.termination.name
    QueueEvents                   = aws_sqs_queue.events.name
    LocksTable                    = aws_dynamodb_table.locks.name
    WorkflowJobsTable             = aws_dynamodb_table.workflow_jobs.name
    CostReportsEnabled            = var.enable_cost_reports ? "true" : "false"
    ServerPassword                = var.server_password
    CostAllocationTag             = var.cost_allocation_tag
    SpotCircuitBreaker            = var.spot_circuit_breaker
    IntegrationStepSecurityApiKey = var.integration_step_security_api_key
    GithubEnterpriseUrl           = var.github_enterprise_url
    VPCId                         = var.vpc_id
    NetworkingStack               = "external"
    InfrastructureSource          = "terraform"
    Ec2InstanceLogGroupArn        = var.ec2_instance_log_group_arn
  })

  # App Runner log group name for CloudWatch dashboard queries
  apprunner_log_group_name = "/aws/apprunner/${aws_apprunner_service.this.service_name}/${aws_apprunner_service.this.service_id}/application"

  # App Runner secrets fetched at runtime.
  runtime_env_secrets = merge(
    {
      RUNS_ON_STACK_CONFIG_JSON = aws_secretsmanager_secret.runs_on_stack_config.arn
    },
    var.app_config_json != "" ? {
      RUNS_ON_APP_CONFIG_JSON = aws_secretsmanager_secret.runs_on_app_config[0].arn
    } : {},
    var.otel_exporter_headers != "" ? {
      OTEL_EXPORTER_OTLP_HEADERS = aws_ssm_parameter.otel_exporter_headers[0].arn
    } : {}
  )
}

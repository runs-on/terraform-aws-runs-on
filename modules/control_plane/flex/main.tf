terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.33"
    }
  }
}

# Local variables
locals {
  github                                = var.github
  runtime                               = var.runtime
  runner                                = var.runner
  operations                            = var.operations
  alerts                                = var.alerts
  common_tags                           = var.tags
  admin_routes_enabled                  = local.operations.enable_admin_routes
  lambda_artifact_dir                   = "${path.module}/../../../lambdas/dist"
  public_ingress_web_acl_arn_trimmed    = trimspace(local.operations.public_ingress_web_acl_arn)
  using_user_managed_public_ingress_waf = local.operations.enable_waf && local.public_ingress_web_acl_arn_trimmed != ""
  using_managed_public_ingress_waf      = local.operations.enable_waf && local.public_ingress_web_acl_arn_trimmed == "" && trimspace(local.github.enterprise_url) == ""
  # Keep the association gate based on input-only state so count stays known during plan.
  public_ingress_web_acl_association_enabled = local.using_user_managed_public_ingress_waf || local.using_managed_public_ingress_waf
  effective_public_ingress_web_acl_arn = local.using_user_managed_public_ingress_waf ? local.public_ingress_web_acl_arn_trimmed : (
    local.using_managed_public_ingress_waf ? aws_wafv2_web_acl.this[0].arn : null
  )

  stack_config_secret_id        = "/runs-on/${var.stack_name}/stack-config"
  license_status_parameter_name = "/${var.stack_name}/license/status"
  license_status_initial_value = jsonencode({
    status      = "verifying"
    valid       = false
    message     = "Verifying"
    errors      = []
    app_version = ""
  })

  public_ingress_stage_name = "prod"
  public_ingress_base_url   = "https://${aws_api_gateway_rest_api.public_ingress.id}.execute-api.${var.region}.amazonaws.com/${local.public_ingress_stage_name}"
  worker_log_group_name     = "/aws/ecs/${var.stack_name}/flexd"
  app_size_presets = {
    small = {
      cpu    = 256
      memory = 512
    }
    medium = {
      cpu    = 256
      memory = 512
    }
    high = {
      cpu    = 512
      memory = 1024
    }
    xhigh = {
      cpu    = 512
      memory = 1024
    }
  }
  app_size_config = local.app_size_presets[local.runtime.size]

  stack_config_base = {
    AwsAccountId                       = var.account_id
    Private                            = local.runtime.private_mode
    GithubOrganization                 = local.github.organization
    Region                             = var.region
    LicenseKey                         = var.license_key
    BucketCache                        = var.extras.cache.bucket_name
    InstanceRoleName                   = var.compute.runner_iam.role_name
    SshAllowed                         = local.runner.ssh_allowed ? "true" : "false"
    LaunchTemplateLinuxDefault         = var.compute.launch_templates.linux_default.id
    LaunchTemplateLinuxDefaultNested   = var.compute.launch_templates.linux_default_nested.id
    LaunchTemplateWindowsDefault       = var.compute.launch_templates.windows_default.id
    LaunchTemplateWindowsDefaultNested = var.compute.launch_templates.windows_default_nested.id
    LaunchTemplateLinuxPrivate         = var.compute.launch_templates.linux_private.id
    LaunchTemplateLinuxPrivateNested   = var.compute.launch_templates.linux_private_nested.id
    LaunchTemplateWindowsPrivate       = var.compute.launch_templates.windows_private.id
    LaunchTemplateWindowsPrivateNested = var.compute.launch_templates.windows_private_nested.id
    PublicSubnetIds                    = var.network.public_subnet_ids
    PrivateSubnetIds                   = var.network.private_subnet_ids
    TopicArn                           = module.alerts.topic_arn
    RunnerCustomTags                   = join(",", local.runner.custom_tags)
    RunnerMaxRuntime                   = local.runner.max_runtime
    RunnerConfigAutoExtendsFrom        = local.runner.config_auto_extends_from
    EbsEncryptionKey                   = local.runner.ebs_encryption_key_id
    AppGithubApiStrategy               = local.github.api_strategy
    AppTag                             = local.runtime.tag
    AppSize                            = local.runtime.size
    GitHubAppsSecretArn                = aws_secretsmanager_secret.runs_on_github_apps.arn
    StackName                          = var.stack_name
    DeploymentMethod                   = "terraform"
    QueueWebhooks                      = aws_sqs_queue.webhooks.name
    QueueSystem                        = aws_sqs_queue.system.name
    QueueEvents                        = aws_sqs_queue.events.name
    LocksTable                         = aws_dynamodb_table.locks.name
    WorkflowJobsTable                  = aws_dynamodb_table.workflow_jobs.name
    JobDiagnosticsResolverFunctionName = aws_lambda_function.job_diagnostics_resolver.function_name
    CostReportsEnabled                 = local.operations.enable_cost_reports ? "true" : "false"
    CostAllocationTag                  = var.cost_allocation_tag
    SpotCircuitBreaker                 = local.operations.spot_circuit_breaker
    IntegrationStepSecurityApiKey      = local.operations.integration_step_security_api_key
    GithubEnterpriseUrl                = local.github.enterprise_url
    VPCId                              = var.network.vpc_id
    NetworkingStack                    = "external"
    IngressURL                         = local.public_ingress_base_url
    ServiceLogGroupName                = local.worker_log_group_name
    Ec2InstanceLogGroupArn             = var.compute.runner_logs.group_arn
  }

  stack_config_json                 = jsonencode(local.stack_config_base)
  stack_config_client_request_token = nonsensitive(sha256(local.stack_config_json))
  stack_config_secret_version       = local.stack_config_client_request_token

  # Keep these as direct env vars because they are consumed before stack config is loaded.
  all_env_vars = merge(
    {
      RUNS_ON_ENV                         = var.environment
      RUNS_ON_STACK_NAME                  = var.stack_name
      RUNS_ON_APP_TAG                     = local.runtime.tag
      RUNS_ON_STACK_CONFIG_SECRET_ARN     = aws_secretsmanager_secret.runs_on_stack_config.arn
      RUNS_ON_STACK_CONFIG_SECRET_VERSION = local.stack_config_secret_version
      OTEL_EXPORTER_OTLP_ENDPOINT         = local.runtime.otel_exporter_endpoint
      OTEL_EXPORTER_OTLP_TEMPORALITY      = local.runtime.otel_exporter_temporality
      OTEL_LOGS_ENABLED                   = local.runtime.otel_logs_enabled ? "true" : "false"
      OTEL_TRACES_ENABLED                 = local.runtime.otel_traces_enabled ? "true" : "false"
      RUNS_ON_LOGGER_LEVEL                = local.runtime.logger_level
    },
    local.runtime.extra_env_vars,
  )

  base_env_vars = { for k, v in local.all_env_vars : k => v if v != "" }
}

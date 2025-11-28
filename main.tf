# main.tf
# Root module for RunsOn infrastructure - orchestrates all submodules

###########################
# CloudFormation Stack for CLI Compatibility
# Exposes all outputs that the RunsOn CLI expects from a CloudFormation deployment
###########################

resource "aws_cloudformation_stack" "runs_on_mock" {
  name = var.stack_name

  # This minimal stack must be created BEFORE App Runner because the RunsOn app
  # calls DescribeStacks on startup. This is temporary until the app/CLI are
  # updated to support OpenTofu deployments natively.

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "RunsOn stack deployed via Terraform/OpenTofu (minimal bootstrap)"

    Resources = {
      MockResource = {
        Type = "AWS::CloudFormation::WaitConditionHandle"
      }
    }

    Outputs = {
      ManagedBy = {
        Value       = "Terraform"
        Description = "Infrastructure management tool"
      }
    }
  })

  tags = merge(
    var.tags,
    {
      Name      = var.stack_name
      ManagedBy = "Terraform"
    }
  )
}

###########################
# Wait for NAT Gateway (Private Networking Only)
# NAT gateways can take time to become fully operational after creation.
# This delay ensures network connectivity is ready before App Runner starts.
###########################

resource "time_sleep" "wait_for_nat" {
  count = var.private_mode != "false" ? 1 : 0

  depends_on = [aws_cloudformation_stack.runs_on_mock]

  create_duration = "60s"
}

###########################
# Storage Module
###########################

module "storage" {
  source = "./modules/storage"

  stack_name            = var.stack_name
  environment           = var.environment
  cost_allocation_tag   = var.cost_allocation_tag
  cache_expiration_days = var.cache_expiration_days
  force_destroy_buckets = var.force_destroy_buckets

  tags = var.tags
}

###########################
# Compute Module
###########################

module "compute" {
  source = "./modules/compute"

  stack_name          = var.stack_name
  environment         = var.environment
  cost_allocation_tag = var.cost_allocation_tag

  # S3 bucket dependencies from storage module
  config_bucket_name = module.storage.config_bucket_name
  config_bucket_arn  = module.storage.config_bucket_arn
  cache_bucket_name  = module.storage.cache_bucket_name
  cache_bucket_arn   = module.storage.cache_bucket_arn

  # Networking configuration
  security_group_ids = local.effective_security_group_ids

  # CloudWatch configuration
  log_group_name     = var.log_group_name
  log_retention_days = var.log_retention_days

  # IAM configuration
  permission_boundary_arn = var.permission_boundary_arn

  # Application versioning
  app_tag       = var.app_tag
  bootstrap_tag = var.bootstrap_tag

  # AMI configuration
  linux_ami_id   = var.linux_ami_id
  windows_ami_id = var.windows_ami_id

  # Instance configuration
  detailed_monitoring_enabled      = var.detailed_monitoring_enabled
  ipv6_enabled                     = var.ipv6_enabled
  ebs_encryption_enabled           = var.ebs_encryption_enabled
  runner_default_disk_size         = var.runner_default_disk_size
  runner_default_volume_throughput = var.runner_default_volume_throughput

  # Private networking
  private_mode = var.private_mode

  # Debug mode
  app_debug = var.app_debug

  # Runner configuration
  runner_max_runtime = var.runner_max_runtime

  # Optional features from optional module
  enable_efs             = var.enable_efs
  efs_file_system_id     = var.enable_efs ? module.optional.efs_file_system_id : ""
  enable_ecr             = var.enable_ecr
  ephemeral_registry_arn = var.enable_ecr ? module.optional.ecr_repository_arn : ""
  ephemeral_registry_uri = var.enable_ecr ? module.optional.ecr_repository_url : ""

  # Custom policy
  custom_policy_json = var.ec2_custom_policy_json

  tags = var.tags
}

###########################
# Optional Module
###########################

module "optional" {
  source = "./modules/optional"

  stack_name  = var.stack_name
  environment = var.environment

  # Feature flags
  enable_efs = var.enable_efs
  enable_ecr = var.enable_ecr

  # Resource protection
  prevent_destroy  = var.prevent_destroy_optional_resources
  force_delete_ecr = var.force_delete_ecr

  # Networking for EFS
  vpc_id             = var.vpc_id
  public_subnet_ids  = var.public_subnet_ids
  security_group_ids = local.effective_security_group_ids

  tags = var.tags
}

###########################
# Core Module
###########################

module "core" {
  source = "./modules/core"

  stack_name          = var.stack_name
  environment         = var.environment
  cost_allocation_tag = var.cost_allocation_tag

  # GitHub configuration
  github_organization   = var.github_organization
  github_enterprise_url = var.github_enterprise_url
  license_key           = var.license_key

  # Networking configuration
  vpc_id             = var.vpc_id
  public_subnet_ids  = var.public_subnet_ids
  private_subnet_ids = var.private_subnet_ids
  security_group_ids = local.effective_security_group_ids

  # S3 bucket dependencies from storage module
  config_bucket_name = module.storage.config_bucket_name
  config_bucket_arn  = module.storage.config_bucket_arn
  cache_bucket_name  = module.storage.cache_bucket_name
  cache_bucket_arn   = module.storage.cache_bucket_arn

  # Compute dependencies
  ec2_instance_role_name             = module.compute.ec2_instance_role_name
  ec2_instance_role_arn              = module.compute.ec2_instance_role_arn
  ec2_instance_profile_arn           = module.compute.ec2_instance_profile_arn
  launch_template_linux_default_id   = module.compute.launch_template_linux_default_id
  launch_template_windows_default_id = module.compute.launch_template_windows_default_id
  launch_template_linux_private_id   = module.compute.launch_template_linux_private_id
  launch_template_windows_private_id = module.compute.launch_template_windows_private_id

  # App Runner configuration
  app_image     = var.app_image
  app_tag       = var.app_tag
  app_cpu       = var.app_cpu
  app_memory    = var.app_memory
  bootstrap_tag = var.bootstrap_tag

  # Networking
  private_mode = var.private_mode

  # Debug mode
  app_debug = var.app_debug

  # Runner configuration
  ssh_allowed                      = var.ssh_allowed
  ec2_queue_size                   = var.ec2_queue_size
  ebs_encryption_key_id            = var.ebs_encryption_key_id
  github_api_strategy              = var.github_api_strategy
  default_admins                   = var.default_admins
  runner_max_runtime               = var.runner_max_runtime
  runner_config_auto_extends_from  = var.runner_config_auto_extends_from
  runner_default_disk_size         = var.runner_default_disk_size
  runner_default_volume_throughput = var.runner_default_volume_throughput
  runner_large_disk_size           = var.runner_large_disk_size
  runner_large_volume_throughput   = var.runner_large_volume_throughput
  runner_custom_tags               = var.runner_custom_tags

  # Operational configuration
  enable_cost_reports  = var.enable_cost_reports
  server_password      = var.server_password
  spot_circuit_breaker = var.spot_circuit_breaker

  # Integrations
  integration_step_security_api_key = var.integration_step_security_api_key
  otel_exporter_endpoint            = var.otel_exporter_endpoint
  otel_exporter_headers             = var.otel_exporter_headers
  logger_level                      = var.logger_level

  # Alerting
  email                   = var.email
  alert_https_endpoint    = var.alert_https_endpoint
  alert_slack_webhook_url = var.alert_slack_webhook_url

  # New Alarms (Parity)
  app_alarm_daily_minutes                    = var.app_alarm_daily_minutes
  sqs_queue_oldest_message_threshold_seconds = var.sqs_queue_oldest_message_threshold_seconds

  tags = var.tags

  # Ensure CF stack exists and NAT gateway is ready before App Runner starts
  depends_on = [
    aws_cloudformation_stack.runs_on_mock,
    time_sleep.wait_for_nat
  ]
}

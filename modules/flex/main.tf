###########################
# Data Sources
###########################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###########################
# Input Validation
###########################

check "private_mode_requires_subnets" {
  assert {
    condition     = var.private_mode == "false" || length(var.private_subnet_ids) > 0
    error_message = "At least one private subnet ID is required when private_mode is not 'false'."
  }
}

check "ghes_waf_requires_public_ingress_web_acl" {
  assert {
    condition     = !var.enable_waf || trimspace(var.github_enterprise_url) == "" || trimspace(var.public_ingress_web_acl_arn) != ""
    error_message = "enable_waf=true with github_enterprise_url requires public_ingress_web_acl_arn. Automatic GitHub webhook IP synchronization is only supported for github.com."
  }
}

###########################
# Local Variables
###########################

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  github_apps_secret = (
    var.github_app_id != null || length(var.github_api_boost_apps) > 0
    ) ? {
    primary = var.github_app_id != null ? {
      app_config = {
        id             = var.github_app_id
        pem            = var.github_app_private_key
        webhook_secret = var.github_app_webhook_secret
        client_id      = var.github_app_client_id
        client_secret  = var.github_app_client_secret
      }
      activation = {
        state      = "ready"
        message    = "GitHub App configured declaratively"
        updated_at = "1970-01-01T00:00:00Z"
      }
    } : null
    boosts = {
      for app_key, app in var.github_api_boost_apps : app_key => {
        app_config = {
          id            = app.github_app_id
          pem           = app.github_app_private_key
          client_id     = app.github_app_client_id
          client_secret = app.github_app_client_secret
        }
        github_app_label = trimspace(try(app.github_app_label, ""))
      }
    }
  } : null

  flex_github = {
    organization   = var.github_organization
    enterprise_url = var.github_enterprise_url
    api_strategy   = var.github_api_strategy
    apps           = local.github_apps_secret
  }

  flex_runtime = {
    image                     = var.app_image
    tag                       = var.app_tag
    maintenance_mode          = var.maintenance_mode
    size                      = var.app_size
    private_mode              = var.private_mode
    ecr_repository_url        = var.app_ecr_repository_url
    custom_policy_arn         = var.app_custom_policy_arn
    otel_exporter_endpoint    = var.otel_exporter_endpoint
    otel_exporter_headers     = var.otel_exporter_headers
    otel_exporter_temporality = var.otel_exporter_temporality
    otel_logs_enabled         = var.otel_logs_enabled
    otel_traces_enabled       = var.otel_traces_enabled
    logger_level              = var.logger_level
    extra_env_vars            = var.extra_env_vars
  }

  flex_runner = {
    ssh_allowed              = var.ssh_allowed
    ebs_encryption_key_id    = var.ebs_encryption_key_id
    max_runtime              = var.runner_max_runtime
    config_auto_extends_from = var.runner_config_auto_extends_from
    custom_tags              = var.runner_custom_tags
  }

  flex_operations = {
    app_budget_daily_usd              = var.app_budget_daily_usd
    enable_cost_reports               = var.enable_cost_reports
    spot_circuit_breaker              = var.spot_circuit_breaker
    integration_step_security_api_key = var.integration_step_security_api_key
    enable_admin_routes               = var.enable_admin_routes
    enable_waf                        = var.enable_waf
    public_ingress_web_acl_arn        = var.public_ingress_web_acl_arn
  }

  flex_alerts = {
    email             = var.email
    slack_webhook_url = var.alert_slack_webhook_url
  }

  # Tags for all resources. Used by CLI for stack-level resource discovery.
  # Do not remove "runs-on-stack-name" tag.
  common_tags = merge(
    var.tags,
    {
      "runs-on-product"         = "flex"
      "runs-on-environment"     = var.environment
      "runs-on-stack-name"      = var.stack_name
      Environment               = var.environment
      (var.cost_allocation_tag) = var.stack_name
    }
  )
}

###########################
# Wait for NAT Gateway (Private Networking Only)
# NAT gateways can take time to become fully operational after creation.
# This delay ensures network connectivity is ready before the worker service starts.
###########################

resource "time_sleep" "wait_for_nat" {
  count = var.private_mode != "false" && var.private_mode_delay != "0s" ? 1 : 0

  create_duration = var.private_mode_delay
}

module "network" {
  source = "../runner/network"

  stack_name         = var.stack_name
  vpc_id             = var.vpc_id
  public_subnet_ids  = var.public_subnet_ids
  private_subnet_ids = var.private_subnet_ids
  security_group_ids = var.security_group_ids
  private_mode       = var.private_mode
  ssh_allowed        = var.ssh_allowed
  ssh_cidr_range     = var.ssh_cidr_range
  tags               = local.common_tags
}

module "extras" {
  source = "../runner/extras"

  stack_name                         = var.stack_name
  cache_expiration_days              = var.cache_expiration_days
  force_destroy_buckets              = var.force_destroy_buckets
  enable_efs                         = var.enable_efs
  enable_ecr                         = var.enable_ecr
  prevent_destroy_optional_resources = var.prevent_destroy_optional_resources
  force_delete_ecr                   = var.force_delete_ecr
  vpc_id                             = var.vpc_id
  public_subnet_ids                  = var.public_subnet_ids
  security_group_ids                 = module.network.network.security_group_ids
  tags                               = local.common_tags
}

module "compute" {
  source = "../runner/compute"

  region     = local.region
  account_id = local.account_id

  stack_name               = var.stack_name
  cost_allocation_tag      = var.cost_allocation_tag
  network                  = module.network.network
  extras                   = module.extras.extras
  log_retention_days       = var.log_retention_days
  permission_boundary_arn  = var.permission_boundary_arn
  runner_custom_policy_arn = var.runner_custom_policy_arn
  enable_bedrock           = var.enable_bedrock
  app_tag                  = var.app_tag
  bootstrap_tag            = var.bootstrap_tag
  ipv6_enabled             = var.ipv6_enabled
  runner_max_runtime       = var.runner_max_runtime
  tags                     = local.common_tags
}

module "control_plane" {
  source = "../control_plane/flex"

  region     = local.region
  account_id = local.account_id

  stack_name          = var.stack_name
  environment         = var.environment
  cost_allocation_tag = var.cost_allocation_tag
  license_key         = var.license_key
  network             = module.network.network
  extras              = module.extras.extras
  compute             = module.compute.compute
  github              = local.flex_github
  runtime             = local.flex_runtime
  runner              = local.flex_runner
  operations          = local.flex_operations
  alerts              = local.flex_alerts
  tags                = local.common_tags

  # Ensure NAT gateway is ready before the worker service starts
  depends_on = [
    time_sleep.wait_for_nat
  ]
}

locals {
  platform = {
    cache             = module.extras.extras.cache
    networking        = module.network.network
    runner_iam        = module.compute.compute.runner_iam
    runner_logs       = module.compute.compute.runner_logs
    launch_templates  = module.compute.compute.launch_templates
    optional_features = module.extras.extras
  }
}

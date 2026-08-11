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

# Check blocks only warn, but this rule must fail invalid plans before apply.
resource "terraform_data" "validate_public_subnets" {
  input = {
    private_mode      = var.private_mode
    public_subnet_ids = var.public_subnet_ids
  }

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_ids) >= 1 || var.private_mode == "only"
      error_message = "At least one public subnet ID is required unless private_mode is \"only\"."
    }
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

  efs_mount_target_subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : var.public_subnet_ids

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
    capacity_provider         = upper(var.app_capacity_provider)
    force_new_deployment      = var.app_force_new_deployment
    private_mode              = var.private_mode
    ecr_repository_url        = var.app_ecr_repository_url
    custom_policy_arns        = var.app_custom_policy_arns
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
    enable_default_dashboard          = var.enable_default_dashboard
    enable_cost_reports               = var.enable_cost_reports
    spot_circuit_breaker              = var.spot_circuit_breaker
    integration_step_security_api_key = var.integration_step_security_api_key
    enable_admin_routes               = var.enable_admin_routes
    enable_waf                        = var.enable_waf
    public_ingress_web_acl_arn        = var.public_ingress_web_acl_arn
    mandatory_extras                  = var.mandatory_extras
  }

  # Match the ECS environment merge and the runtime's boolean parsing so
  # diagnostics describe the process configuration after extra_env_vars wins.
  flex_effective_otel_exporter_endpoint = trimspace(lookup(
    var.extra_env_vars,
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    var.otel_exporter_endpoint,
  ))
  flex_effective_otel_headers_configured = anytrue(flatten([
    for headers in [
      var.otel_exporter_headers,
      lookup(var.extra_env_vars, "OTEL_EXPORTER_OTLP_HEADERS", ""),
      ] : [
      for pair in split(",", headers) :
      trimspace(split("=", pair)[0]) != "" &&
      trimspace(join("=", slice(split("=", pair), 1, length(split("=", pair))))) != ""
    ]
  ]))
  flex_effective_otel_temporality_raw = trimspace(lookup(
    var.extra_env_vars,
    "OTEL_EXPORTER_OTLP_TEMPORALITY",
    var.otel_exporter_temporality,
  ))
  flex_effective_otel_logs_raw = lower(trimspace(lookup(
    var.extra_env_vars,
    "OTEL_LOGS_ENABLED",
    var.otel_logs_enabled ? "true" : "false",
  )))
  flex_effective_otel_traces_raw = lower(trimspace(lookup(
    var.extra_env_vars,
    "OTEL_TRACES_ENABLED",
    var.otel_traces_enabled ? "true" : "false",
  )))
  flex_effective_otel_logs_enabled = (
    contains(["1", "true", "yes", "on"], local.flex_effective_otel_logs_raw) ? true :
    contains(["0", "false", "no", "off"], local.flex_effective_otel_logs_raw) ? false :
    local.flex_effective_otel_exporter_endpoint != ""
  )
  flex_effective_otel_traces_enabled = !contains(
    ["0", "false", "no", "off"],
    local.flex_effective_otel_traces_raw,
  )
  flex_effective_logger_level_raw = lookup(
    var.extra_env_vars,
    "RUNS_ON_LOGGER_LEVEL",
    var.logger_level,
  )
  flex_effective_logger_level = contains(
    ["trace", "debug", "info", "warn"],
    local.flex_effective_logger_level_raw,
  ) ? local.flex_effective_logger_level_raw : "info"
  flex_ebs_encryption_key = lower(trimspace(var.ebs_encryption_key_id))
  flex_ebs_encryption_mode = local.flex_ebs_encryption_key == "" ? "unspecified" : (
    local.flex_ebs_encryption_key == "alias/aws/ebs" ||
    can(regex("^arn:[^:]+:kms:[^:]+:[^:]+:alias/aws/ebs$", local.flex_ebs_encryption_key))
    ? "aws-managed"
    : "explicit"
  )
  flex_effective_runner_custom_tags_configured = anytrue(flatten([
    for raw_tag in var.runner_custom_tags : [
      for tag in split(",", trimspace(raw_tag)) :
      tag != "" && !startswith(tag, "runs-on-")
    ]
  ]))

  flex_diagnostic_settings = {
    schema_version    = 1
    app_tag           = var.app_tag
    deployment_method = "terraform"
    cache = {
      isolation_enabled         = var.enable_cache_isolation
      expiration_days           = var.cache_expiration_days
      bucket_versioning_enabled = var.cache_bucket_versioning_enabled
      mandatory_extras          = var.mandatory_extras
    }
    sticky_disk = {
      isolation_enabled       = var.enable_stickydisk_isolation
      configured_runner_count = null
    }
    storage = {
      ebs_encryption_mode = local.flex_ebs_encryption_mode
      efs_enabled         = var.enable_efs
    }
    buildkit = {
      ephemeral_registry_enabled = var.enable_ecr
      pull_through_rule_count    = length(var.ecr_pull_through_cache_rules)
      docker_hub_mirror_enabled = anytrue([
        for rule in values(var.ecr_pull_through_cache_rules) :
        lower(trimspace(rule.upstream_registry_url)) == "registry-1.docker.io" &&
        try(trimspace(rule.upstream_repository_prefix), "") == ""
      ])
    }
    runner = {
      max_runtime_minutes         = var.runner_max_runtime
      config_auto_extends_enabled = !contains(["", "."], var.runner_config_auto_extends_from)
      custom_policy_count         = length(var.runner_custom_policy_arns)
      custom_tags_configured      = local.flex_effective_runner_custom_tags_configured
      bedrock_enabled             = var.enable_bedrock
    }
    scheduling = {
      spot_circuit_breaker = var.spot_circuit_breaker
    }
    network = {
      private_mode         = var.private_mode
      ipv6_enabled         = var.ipv6_enabled
      ssh_allowed          = var.ssh_allowed
      public_subnet_count  = length(var.public_subnet_ids)
      private_subnet_count = length(var.private_subnet_ids)
    }
    runtime = {
      app_size            = var.app_size
      capacity_provider   = upper(var.app_capacity_provider)
      maintenance_mode    = var.maintenance_mode
      github_api_strategy = var.github_api_strategy
    }
    telemetry = {
      exporter_configured      = local.flex_effective_otel_exporter_endpoint != ""
      headers_configured       = local.flex_effective_otel_headers_configured
      temporality              = local.flex_effective_otel_temporality_raw == "" ? "cumulative" : local.flex_effective_otel_temporality_raw
      logs_enabled             = local.flex_effective_otel_logs_enabled
      traces_enabled           = local.flex_effective_otel_traces_enabled
      logger_level             = local.flex_effective_logger_level
      ec2_log_group_configured = trimspace(module.compute.compute.runner_logs.group_name) != ""
    }
    integrations = {
      step_security_configured = trimspace(var.integration_step_security_api_key) != ""
    }
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
  cache_bucket_namespace             = var.cache_bucket_namespace
  cache_bucket_versioning_enabled    = var.cache_bucket_versioning_enabled
  force_destroy_buckets              = var.force_destroy_buckets
  enable_efs                         = var.enable_efs
  enable_ecr                         = var.enable_ecr
  ecr_pull_through_cache_rules       = var.ecr_pull_through_cache_rules
  prevent_destroy_optional_resources = var.prevent_destroy_optional_resources
  vpc_id                             = var.vpc_id
  public_subnet_ids                  = local.efs_mount_target_subnet_ids
  security_group_ids                 = module.network.network.security_group_ids
  tags                               = local.common_tags
}

module "compute" {
  source = "../runner/compute"

  region     = local.region
  account_id = local.account_id

  stack_name                      = var.stack_name
  cost_allocation_tag             = var.cost_allocation_tag
  network                         = module.network.network
  extras                          = module.extras.extras
  log_retention_days              = var.log_retention_days
  permission_boundary_arn         = var.permission_boundary_arn
  runner_custom_policy_arns       = var.runner_custom_policy_arns
  runner_ssm_policy_override_json = var.runner_ssm_policy_override_json
  enable_bedrock                  = var.enable_bedrock
  enable_cache_isolation          = var.enable_cache_isolation
  enable_stickydisk_isolation     = var.enable_stickydisk_isolation
  app_tag                         = var.app_tag
  bootstrap_tag                   = var.bootstrap_tag
  ipv6_enabled                    = var.ipv6_enabled
  runner_max_runtime              = var.runner_max_runtime
  tags                            = local.common_tags
}

module "control_plane" {
  source = "../control_plane/flex"

  region     = local.region
  account_id = local.account_id

  stack_name             = var.stack_name
  environment            = var.environment
  cost_allocation_tag    = var.cost_allocation_tag
  license_key            = var.license_key
  network                = module.network.network
  extras                 = module.extras.extras
  compute                = module.compute.compute
  github                 = local.flex_github
  runtime                = local.flex_runtime
  runner                 = local.flex_runner
  operations             = local.flex_operations
  diagnostic_settings    = local.flex_diagnostic_settings
  alerts                 = local.flex_alerts
  enable_cache_isolation = var.enable_cache_isolation
  tags                   = local.common_tags

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

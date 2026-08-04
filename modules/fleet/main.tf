data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

check "private_mode_requires_subnets" {
  assert {
    condition     = var.private_mode == "false" || length(var.private_subnet_ids) > 0
    error_message = "At least one private subnet ID is required when private_mode is not false."
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

locals {
  region = data.aws_region.current.region

  # These patterns mirror the control plane's sticky-label parser so Terraform
  # rejects bad Fleet catalog entries before deploying an unusable runner.
  sticky_disk_name_pattern           = "^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$"
  sticky_disk_size_pattern           = "^\\+?[1-9][0-9]*(gb|g|tb)$"
  sticky_disk_throughput_pattern     = "^[+-]?[0-9]+(mibps|mbs|mbps)$"
  sticky_disk_iops_pattern           = "^[+-]?[0-9]+iops$"
  sticky_disk_initialization_pattern = "^((1[0-9][0-9]|2[0-9][0-9]|300)mibps-init|lazy-init)$"
  sticky_disk_setting_pattern        = "^(gp3|gp2|io1|io2|st1|sc1|standard|\\+?[1-9][0-9]*(gb|g|tb)|[+-]?[0-9]+(mibps|mbs|mbps|iops)|(1[0-9][0-9]|2[0-9][0-9]|300)mibps-init|lazy-init)$"
  sticky_disk_volume_types           = ["gp3", "gp2", "io1", "io2", "st1", "sc1", "standard"]
  fleet_runner_sticky_specs = {
    for name, runner in var.runners :
    name => try(trimspace(tostring(runner.sticky)), "")
    if try(trimspace(tostring(runner.sticky)), "") != ""
  }
  fleet_runner_invalid_sticky_types = [
    for name, runner in var.runners : name
    if can(runner.sticky) && try(runner.sticky != null, false) && !can(tostring(runner.sticky))
  ]
  fleet_runner_sticky_parts = {
    for name, spec in local.fleet_runner_sticky_specs :
    name => [for part in split(":", spec) : lower(trimspace(part))]
  }
  fleet_runner_sticky_setting_parts = {
    for name, parts in local.fleet_runner_sticky_parts :
    name => can(regex(local.sticky_disk_setting_pattern, parts[0])) ? parts : slice(parts, 1, length(parts))
  }

  fleet_github = {
    app_id          = var.github_app_id
    app_private_key = var.github_app_private_key
    enterprise_pat  = var.github_enterprise_pat
    base_url        = var.github_base_url
    enterprise      = var.github_enterprise_name
    license_key     = var.license_key
  }

  fleet_alerts = {
    email             = var.email
    slack_webhook_url = var.alert_slack_webhook_url
  }

  fleet_catalog = {
    images  = var.images
    runners = var.runners
    fleets  = var.fleets
  }

  fleet_runtime = {
    image                     = var.runtime_image
    size                      = var.app_size
    capacity_provider         = upper(var.app_capacity_provider)
    maintenance_mode          = var.maintenance_mode
    log_retention_days        = var.log_retention_days
    otel_exporter_endpoint    = var.otel_exporter_endpoint
    otel_exporter_headers     = var.otel_exporter_headers
    otel_exporter_temporality = var.otel_exporter_temporality
    otel_logs_enabled         = var.otel_logs_enabled
    otel_traces_enabled       = var.otel_traces_enabled
    extra_env_vars            = var.extra_env_vars
  }

  fleet_control_plane = {
    environment          = var.environment
    private_mode         = var.private_mode
    cost_allocation_tag  = var.cost_allocation_tag
    app_tag              = var.app_tag
    runner_custom_tags   = var.runner_custom_tags
    spot_circuit_breaker = var.spot_circuit_breaker
  }

  # Match the ECS environment merge and the runtime's boolean parsing so
  # diagnostics describe the process configuration after extra_env_vars wins.
  fleet_effective_otel_exporter_endpoint = trimspace(lookup(
    var.extra_env_vars,
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    var.otel_exporter_endpoint,
  ))
  fleet_effective_otel_headers_configured = anytrue(flatten([
    for headers in [
      var.otel_exporter_headers,
      lookup(var.extra_env_vars, "OTEL_EXPORTER_OTLP_HEADERS", ""),
      ] : [
      for pair in split(",", headers) :
      trimspace(split("=", pair)[0]) != "" &&
      trimspace(join("=", slice(split("=", pair), 1, length(split("=", pair))))) != ""
    ]
  ]))
  fleet_effective_otel_temporality_raw = trimspace(lookup(
    var.extra_env_vars,
    "OTEL_EXPORTER_OTLP_TEMPORALITY",
    var.otel_exporter_temporality,
  ))
  fleet_effective_otel_logs_raw = lower(trimspace(lookup(
    var.extra_env_vars,
    "OTEL_LOGS_ENABLED",
    var.otel_logs_enabled ? "true" : "false",
  )))
  fleet_effective_otel_traces_raw = lower(trimspace(lookup(
    var.extra_env_vars,
    "OTEL_TRACES_ENABLED",
    var.otel_traces_enabled ? "true" : "false",
  )))
  fleet_effective_otel_logs_enabled = (
    contains(["1", "true", "yes", "on"], local.fleet_effective_otel_logs_raw) ? true :
    contains(["0", "false", "no", "off"], local.fleet_effective_otel_logs_raw) ? false :
    local.fleet_effective_otel_exporter_endpoint != ""
  )
  fleet_effective_otel_traces_enabled = !contains(
    ["0", "false", "no", "off"],
    local.fleet_effective_otel_traces_raw,
  )
  fleet_effective_runner_custom_tags_configured = anytrue([
    for tag in var.runner_custom_tags :
    trimspace(tag) != "" && !startswith(tag, "runs-on-")
  ])

  fleet_diagnostic_settings = {
    schema_version    = 1
    app_tag           = var.app_tag
    deployment_method = "terraform"
    cache = {
      isolation_enabled         = var.enable_cache_isolation
      expiration_days           = var.cache_expiration_days
      bucket_versioning_enabled = var.cache_bucket_versioning_enabled
      mandatory_extras          = []
    }
    sticky_disk = {
      isolation_enabled       = var.enable_stickydisk_isolation
      configured_runner_count = length(local.fleet_runner_sticky_specs)
    }
    storage = {
      ebs_encryption_mode = "unspecified"
      efs_enabled         = false
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
      max_runtime_minutes    = var.runner_max_runtime
      custom_policy_count    = length(var.runner_custom_policy_arns)
      custom_tags_configured = local.fleet_effective_runner_custom_tags_configured
      bedrock_enabled        = var.enable_bedrock
    }
    scheduling = {
      spot_circuit_breaker = trimspace(var.spot_circuit_breaker) == "" ? "2/15/30" : var.spot_circuit_breaker
    }
    network = {
      private_mode         = var.private_mode
      ipv6_enabled         = var.ipv6_enabled
      ssh_allowed          = var.ssh_allowed
      public_subnet_count  = length(var.public_subnet_ids)
      private_subnet_count = length(var.private_subnet_ids)
    }
    runtime = {
      app_size          = var.app_size
      capacity_provider = upper(var.app_capacity_provider)
      maintenance_mode  = var.maintenance_mode
    }
    telemetry = {
      exporter_configured      = local.fleet_effective_otel_exporter_endpoint != ""
      headers_configured       = local.fleet_effective_otel_headers_configured
      temporality              = local.fleet_effective_otel_temporality_raw == "" ? "cumulative" : local.fleet_effective_otel_temporality_raw
      logs_enabled             = local.fleet_effective_otel_logs_enabled
      traces_enabled           = local.fleet_effective_otel_traces_enabled
      ec2_log_group_configured = trimspace(module.compute.compute.runner_logs.group_name) != ""
    }
    integrations = {
      step_security_configured = trimspace(var.integration_step_security_api_key) != ""
    }
  }

  common_tags = merge(
    var.tags,
    {
      "runs-on-stack-name"      = var.stack_name
      "runs-on-environment"     = var.environment
      (var.cost_allocation_tag) = var.stack_name
    }
  )
}

# Unlike a check block, this precondition fails the plan. Runtime validation
# remains authoritative for non-Terraform deployments and future parser drift.
resource "terraform_data" "validate_runner_sticky_specs" {
  input = {
    specs         = local.fleet_runner_sticky_specs
    invalid_types = local.fleet_runner_invalid_sticky_types
  }

  lifecycle {
    precondition {
      condition = length(local.fleet_runner_invalid_sticky_types) == 0 && alltrue([
        for name, parts in local.fleet_runner_sticky_parts :
        (can(regex(local.sticky_disk_setting_pattern, parts[0])) || can(regex(local.sticky_disk_name_pattern, parts[0]))) &&
        length(local.fleet_runner_sticky_setting_parts[name]) > 0 &&
        alltrue([
          for part in local.fleet_runner_sticky_setting_parts[name] :
          can(regex(local.sticky_disk_setting_pattern, part))
        ]) &&
        length([
          for part in local.fleet_runner_sticky_setting_parts[name] : part
          if can(regex(local.sticky_disk_size_pattern, part))
        ]) == 1 &&
        length([
          for part in local.fleet_runner_sticky_setting_parts[name] : part
          if contains(local.sticky_disk_volume_types, part)
        ]) <= 1 &&
        length([
          for part in local.fleet_runner_sticky_setting_parts[name] : part
          if can(regex(local.sticky_disk_throughput_pattern, part))
        ]) <= 1 &&
        length([
          for part in local.fleet_runner_sticky_setting_parts[name] : part
          if can(regex(local.sticky_disk_iops_pattern, part))
        ]) <= 1 &&
        length([
          for part in local.fleet_runner_sticky_setting_parts[name] : part
          if can(regex(local.sticky_disk_initialization_pattern, part))
        ]) <= 1
      ])
      error_message = "Each Fleet runner sticky value must be a string using [name:]<size>, optionally followed by one volume type, MiB/s throughput, IOPS, and one 100-300mibps-init or lazy-init setting."
    }
  }
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
  enable_efs                         = false
  enable_ecr                         = var.enable_ecr
  ecr_pull_through_cache_rules       = var.ecr_pull_through_cache_rules
  prevent_destroy_optional_resources = false
  vpc_id                             = var.vpc_id
  public_subnet_ids                  = var.public_subnet_ids
  security_group_ids                 = module.network.network.security_group_ids
  tags                               = local.common_tags
}

module "compute" {
  source = "../runner/compute"

  region     = local.region
  account_id = data.aws_caller_identity.current.account_id

  stack_name                  = var.stack_name
  cost_allocation_tag         = var.cost_allocation_tag
  network                     = module.network.network
  extras                      = module.extras.extras
  log_retention_days          = var.log_retention_days
  permission_boundary_arn     = var.permission_boundary_arn
  runner_custom_policy_arns   = var.runner_custom_policy_arns
  enable_bedrock              = var.enable_bedrock
  enable_cache_isolation      = var.enable_cache_isolation
  enable_stickydisk_isolation = var.enable_stickydisk_isolation
  bootstrap_tag               = var.bootstrap_tag
  app_tag                     = var.app_tag
  runner_max_runtime          = var.runner_max_runtime
  ipv6_enabled                = var.ipv6_enabled
  tags                        = local.common_tags
}

module "control_plane" {
  source = "../control_plane/fleet"

  region     = local.region
  account_id = data.aws_caller_identity.current.account_id

  stack_name                        = var.stack_name
  network                           = module.network.network
  extras                            = module.extras.extras
  compute                           = module.compute.compute
  github                            = local.fleet_github
  alerts                            = local.fleet_alerts
  catalog                           = local.fleet_catalog
  runtime                           = local.fleet_runtime
  integration_step_security_api_key = var.integration_step_security_api_key
  control_plane                     = local.fleet_control_plane
  diagnostic_settings               = local.fleet_diagnostic_settings
  enable_cache_isolation            = var.enable_cache_isolation
  tags                              = local.common_tags
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

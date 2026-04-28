data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

check "private_mode_requires_subnets" {
  assert {
    condition     = var.private_mode == "false" || length(var.private_subnet_ids) > 0
    error_message = "At least one private subnet ID is required when private_mode is not false."
  }
}

locals {
  region = data.aws_region.current.region

  fleet_github = {
    app_id          = var.github_app_id
    app_private_key = var.github_app_private_key
    enterprise_pat  = var.github_enterprise_pat
    base_url        = var.github_base_url
    enterprise      = var.enterprise
  }

  fleet_catalog = {
    images  = var.images
    runners = var.runners
    pools   = var.pools
  }

  fleet_runtime = {
    image              = var.runtime_image
    size               = var.app_size
    log_retention_days = var.log_retention_days
    extra_env_vars     = var.extra_env_vars
  }

  fleet_control_plane = {
    environment         = var.environment
    private_mode        = var.private_mode
    cost_allocation_tag = var.cost_allocation_tag
    app_tag             = var.app_tag
    runner_custom_tags  = var.runner_custom_tags
  }

  common_tags = merge(
    var.tags,
    {
      "runs-on-product"         = "fleet"
      "runs-on-stack-name"      = var.stack_name
      "runs-on-environment"     = var.environment
      Environment               = var.environment
      (var.cost_allocation_tag) = var.stack_name
    }
  )
}

module "network" {
  source = "../modules/runner/network"

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
  source = "../modules/runner/extras"

  stack_name                         = var.stack_name
  cache_expiration_days              = var.cache_expiration_days
  force_destroy_buckets              = var.force_destroy_buckets
  enable_efs                         = false
  enable_ecr                         = false
  prevent_destroy_optional_resources = false
  force_delete_ecr                   = false
  vpc_id                             = var.vpc_id
  public_subnet_ids                  = var.public_subnet_ids
  security_group_ids                 = module.network.network.security_group_ids
  tags                               = local.common_tags
}

module "compute" {
  source = "../modules/runner/compute"

  region     = local.region
  account_id = data.aws_caller_identity.current.account_id

  stack_name               = var.stack_name
  cost_allocation_tag      = var.cost_allocation_tag
  network                  = module.network.network
  extras                   = module.extras.extras
  log_retention_days       = var.log_retention_days
  permission_boundary_arn  = var.permission_boundary_arn
  runner_custom_policy_arn = var.runner_custom_policy_arn
  enable_bedrock           = var.enable_bedrock
  bootstrap_tag            = var.bootstrap_tag
  app_tag                  = var.app_tag
  runner_max_runtime       = var.runner_max_runtime
  ipv6_enabled             = var.ipv6_enabled
  tags                     = local.common_tags
}

module "control_plane" {
  source = "../modules/control_plane/fleet"

  region     = local.region
  account_id = data.aws_caller_identity.current.account_id

  stack_name    = var.stack_name
  network       = module.network.network
  extras        = module.extras.extras
  compute       = module.compute.compute
  github        = local.fleet_github
  catalog       = local.fleet_catalog
  runtime       = local.fleet_runtime
  control_plane = local.fleet_control_plane
  tags          = local.common_tags
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

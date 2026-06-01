terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

locals {
  github        = var.github
  runtime       = var.runtime
  control_plane = var.control_plane
  # Fleet has one routing environment per stack. Normalize any fleet-level env
  # value before persisting the runtime config so lanes cannot drift by entry.
  catalog = {
    images  = var.catalog.images
    runners = var.catalog.runners
    fleets = {
      for fleet_name, fleet in var.catalog.fleets : fleet_name => merge(fleet, {
        env = var.control_plane.environment
      })
    }
  }
  config_secret_name = "/runs-on/${var.stack_name}/fleet-config"
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
  runtime_size_config           = local.app_size_presets[local.runtime.size]
  workflow_target_contract      = "runs-on/fleet=<fleet-name>/env=${local.control_plane.environment}"
  github_app_id_set             = local.github.app_id != null
  github_private_key_set        = try(trimspace(local.github.app_private_key), "") != ""
  github_enterprise_pat_set     = try(trimspace(local.github.enterprise_pat), "") != ""
  normalized_github_base_url    = trimspace(local.github.base_url) != "" ? trimspace(local.github.base_url) : "https://github.com"
  normalized_enterprise         = try(trimspace(local.github.enterprise), "")
  license_status_parameter_name = "/${var.stack_name}/license/status"
  license_status_initial_value = jsonencode({
    status      = "verifying"
    valid       = false
    message     = "License verification pending"
    errors      = []
    app_version = local.control_plane.app_tag
  })

  secret_payload = {
    schema_version        = 4
    github_app_id         = local.github.app_id
    github_private_key    = local.github.app_private_key
    github_enterprise_pat = local.github.enterprise_pat
    license_key           = local.github.license_key
    github_base_url       = local.normalized_github_base_url
    enterprise            = local.normalized_enterprise
    app_size              = local.runtime.size
    environment           = local.control_plane.environment
    integrations = {
      stepSecurityApiKey = var.integration_step_security_api_key
    }
    images  = local.catalog.images
    runners = local.catalog.runners
    fleets  = local.catalog.fleets
    infra = {
      aws_account_id                         = var.account_id
      aws_region                             = var.region
      stack_name                             = var.stack_name
      bucket_cache                           = var.extras.cache.bucket_name
      claim_table_name                       = aws_dynamodb_table.claims.name
      job_diagnostics_resolver_function_name = aws_lambda_function.job_diagnostics_resolver.function_name
      app_tag                                = local.control_plane.app_tag
      deployment_method                      = "terraform"
      networking_stack                       = var.stack_name
      private_mode                           = local.control_plane.private_mode
      cost_allocation_tag                    = local.control_plane.cost_allocation_tag
      runner_custom_tags                     = local.control_plane.runner_custom_tags
      ebs_encryption_key                     = ""
      instance_role_name                     = var.compute.runner_iam.role_name
      instance_role_id                       = var.compute.runner_iam.role_id
      ec2_instance_log_group                 = var.compute.runner_logs.group_name
      service_log_group_name                 = "/aws/ecs/${var.stack_name}/fleetd"
      alert_topic_arn                        = module.alerts.topic_arn
      public_subnet_ids                      = var.network.public_subnet_ids
      private_subnet_ids                     = var.network.private_subnet_ids
      launch_templates = {
        for name, template in var.compute.launch_templates : name => template.id
      }
    }
  }
  config_secret_json    = jsonencode(local.secret_payload)
  config_secret_version = nonsensitive(sha256(local.config_secret_json))

  fleet_extra_policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ]
      Resource = [aws_secretsmanager_secret.config.arn]
    },
    {
      Effect = "Allow"
      Action = [
        "dynamodb:DescribeTable",
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query",
        "dynamodb:TransactWriteItems",
      ]
      Resource = [
        aws_dynamodb_table.claims.arn,
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:PutParameter",
      ]
      Resource = [aws_ssm_parameter.license_status.arn]
    },
    {
      Effect = "Allow"
      Action = [
        "sns:Publish",
      ]
      Resource = module.alerts.topic_arn
    },
  ]
}

check "fleet_runners_exist" {
  assert {
    condition     = alltrue([for fleet_name, fleet in local.catalog.fleets : contains(keys(local.catalog.runners), try(fleet.runner, ""))])
    error_message = "Each fleet.runner must reference a runner name defined in runners."
  }
}

check "github_auth_mode_is_valid" {
  assert {
    condition = (
      local.github_app_id_set &&
      local.github_private_key_set &&
      !local.github_enterprise_pat_set
      ) || (
      !local.github_app_id_set &&
      !local.github_private_key_set &&
      local.github_enterprise_pat_set
    )
    error_message = "Set github_app_id with github_app_private_key for organization mode, or set github_enterprise_pat for enterprise mode."
  }
}

check "enterprise_mode_contract_is_valid" {
  assert {
    condition     = local.github_enterprise_pat_set ? local.normalized_enterprise != "" : local.normalized_enterprise == ""
    error_message = "github_enterprise_name is required when github_enterprise_pat is set and must be omitted when using GitHub App organization mode."
  }
}

check "github_enterprise_pat_prefix_is_valid" {
  assert {
    condition     = local.github_enterprise_pat_set ? startswith(local.github.enterprise_pat, "ghp_") : true
    error_message = "github_enterprise_pat must start with ghp_ when set."
  }
}

check "app_size_is_valid" {
  assert {
    condition     = contains(keys(local.app_size_presets), local.runtime.size)
    error_message = "runtime.size must be one of: small, medium, high, xhigh."
  }
}

resource "aws_secretsmanager_secret" "config" {
  name                    = local.config_secret_name
  recovery_window_in_days = 0
  tags                    = var.tags
}

removed {
  # Preserve pre-materializer config versions in Secrets Manager while removing
  # provider ownership of staging labels from existing Fleet state.
  from = aws_secretsmanager_secret_version.config
}

resource "aws_ssm_parameter" "license_status" {
  name      = local.license_status_parameter_name
  type      = "String"
  value     = local.license_status_initial_value
  overwrite = true
  tags      = var.tags

  lifecycle {
    # Runtime license checks own the live status; Terraform only ensures the path exists.
    ignore_changes = [value]
  }
}

resource "aws_dynamodb_table" "claims" {
  name         = "${var.stack_name}-fleet-claims"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "workflow_run_id"
    type = "N"
  }

  attribute {
    name = "updated_at_unix"
    type = "N"
  }

  global_secondary_index {
    name            = "workflow-run-id-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "workflow_run_id"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "updated_at_unix"
      key_type       = "RANGE"
    }
  }

  ttl {
    enabled        = true
    attribute_name = "ttl"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-fleet-claims"
    }
  )
}

module "runtime" {
  source = "../runtime"

  region     = var.region
  account_id = var.account_id
  stack_name = var.stack_name

  cluster_name               = var.stack_name
  service_name               = "fleetd"
  task_definition_family     = "${var.stack_name}-fleetd"
  execution_role_name        = "${var.stack_name}-fleet-execution-role"
  task_role_name             = "${var.stack_name}-fleet-role"
  task_policy_name           = "${var.stack_name}-fleet"
  runner_instance_role_arn   = var.compute.runner_iam.role_arn
  cache_bucket_arn           = var.extras.cache.bucket_arn
  extra_task_role_statements = local.fleet_extra_policy_statements
  log_group_name             = "/aws/ecs/${var.stack_name}/fleetd"
  log_retention_days         = local.runtime.log_retention_days
  cpu                        = local.runtime_size_config.cpu
  memory                     = local.runtime_size_config.memory
  desired_count              = local.runtime.maintenance_mode ? 0 : 1
  capacity_provider          = local.runtime.capacity_provider
  assign_public_ip           = local.control_plane.private_mode == "false"
  security_group_ids         = var.network.security_group_ids
  subnet_ids                 = local.control_plane.private_mode == "false" ? var.network.public_subnet_ids : var.network.private_subnet_ids
  tags                       = var.tags
  container_definitions = [
    {
      name       = "fleetd"
      image      = local.runtime.image
      essential  = true
      entryPoint = ["/app/dist/fleetd"]
      environment = [
        for key, value in merge(
          {
            RUNS_ON_FLEET_CONFIG_SECRET_ARN     = aws_secretsmanager_secret.config.arn
            RUNS_ON_FLEET_CONFIG_SECRET_VERSION = local.config_secret_version
            RUNS_ON_FLEET_HEARTBEAT_PATH        = "/tmp/runs-on-fleet-heartbeat"
          },
          local.runtime.extra_env_vars,
        ) : { name = key, value = value }
        if value != ""
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/aws/ecs/${var.stack_name}/fleetd"
          awslogs-region        = var.region
          awslogs-stream-prefix = "fleetd"
        }
      }
    }
  ]

  depends_on = [
    aws_lambda_invocation.config_materializer,
  ]
}

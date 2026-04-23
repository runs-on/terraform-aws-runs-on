terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

locals {
  github        = var.github
  catalog       = var.catalog
  runtime       = var.runtime
  control_plane = var.control_plane
  app_size_presets = {
    small = {
      cpu    = 256
      memory = 512
    }
    medium = {
      cpu    = 512
      memory = 1024
    }
    high = {
      cpu    = 1024
      memory = 2048
    }
    xhigh = {
      cpu    = 2048
      memory = 4096
    }
  }
  runtime_size_config        = local.app_size_presets[local.runtime.size]
  workflow_target_contract   = "runs-on/pool=<pool-name>/env=${local.control_plane.environment}"
  github_app_id_set          = local.github.app_id != null
  github_private_key_set     = try(trimspace(local.github.app_private_key), "") != ""
  github_enterprise_pat_set  = try(trimspace(local.github.enterprise_pat), "") != ""
  normalized_github_base_url = trimspace(local.github.base_url) != "" ? trimspace(local.github.base_url) : "https://github.com"
  normalized_enterprise      = try(trimspace(local.github.enterprise), "")

  secret_payload = {
    schema_version        = 4
    github_app_id         = local.github.app_id
    github_private_key    = local.github.app_private_key
    github_enterprise_pat = local.github.enterprise_pat
    github_base_url       = local.normalized_github_base_url
    enterprise            = local.normalized_enterprise
    app_size              = local.runtime.size
    environment           = local.control_plane.environment
    images                = local.catalog.images
    runners               = local.catalog.runners
    pools                 = local.catalog.pools
    infra = {
      aws_region             = var.region
      stack_name             = var.stack_name
      bucket_cache           = var.extras.cache.bucket_name
      claim_table_name       = aws_dynamodb_table.claims.name
      app_tag                = local.control_plane.app_tag
      networking_stack       = var.stack_name
      private_mode           = local.control_plane.private_mode
      cost_allocation_tag    = local.control_plane.cost_allocation_tag
      runner_custom_tags     = local.control_plane.runner_custom_tags
      ebs_encryption_key     = ""
      instance_role_name     = var.compute.runner_iam.role_name
      instance_role_id       = var.compute.runner_iam.role_id
      ec2_instance_log_group = var.compute.runner_logs.group_name
      public_subnet_ids      = var.network.public_subnet_ids
      private_subnet_ids     = var.network.private_subnet_ids
      launch_templates = {
        for name, template in var.compute.launch_templates : name => template.id
      }
    }
  }

  scaleset_extra_policy_statements = [
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
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query",
      ]
      Resource = [
        aws_dynamodb_table.claims.arn,
        "${aws_dynamodb_table.claims.arn}/index/*",
      ]
    },
  ]
}

check "pool_runners_exist" {
  assert {
    condition     = alltrue([for pool_name, pool in local.catalog.pools : contains(keys(local.catalog.runners), try(pool.runner, ""))])
    error_message = "Each pool.runner must reference a runner name defined in runners."
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
    error_message = "enterprise is required when github_enterprise_pat is set and must be omitted when using GitHub App organization mode."
  }
}

check "app_size_is_valid" {
  assert {
    condition     = contains(keys(local.app_size_presets), local.runtime.size)
    error_message = "runtime.size must be one of: small, medium, high, xhigh."
  }
}

resource "aws_secretsmanager_secret" "config" {
  name = "${var.stack_name}/fleet-config"
  tags = var.tags
}

resource "aws_dynamodb_table" "claims" {
  name         = "${var.stack_name}-fleet-claims"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "claim_key"

  attribute {
    name = "claim_key"
    type = "S"
  }

  attribute {
    name = "target_key"
    type = "S"
  }

  attribute {
    name = "updated_at_unix"
    type = "N"
  }

  global_secondary_index {
    name            = "by-target-updated-at"
    projection_type = "ALL"

    key_schema {
      attribute_name = "target_key"
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

resource "aws_secretsmanager_secret_version" "config" {
  secret_id     = aws_secretsmanager_secret.config.id
  secret_string = jsonencode(local.secret_payload)
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
  extra_task_role_statements = local.scaleset_extra_policy_statements
  log_group_name             = "/aws/ecs/${var.stack_name}/fleetd"
  log_retention_days         = local.runtime.log_retention_days
  cpu                        = local.runtime_size_config.cpu
  memory                     = local.runtime_size_config.memory
  desired_count              = 1
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
        { name = "RUNS_ON_SCALESET_CONFIG_SECRET_ARN", value = aws_secretsmanager_secret.config.arn },
        { name = "RUNS_ON_SCALESET_HEARTBEAT_PATH", value = "/tmp/runs-on-fleet-heartbeat" }
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
    aws_secretsmanager_secret_version.config,
  ]
}

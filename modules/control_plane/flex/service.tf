# ECS worker service for RunsOn Flex control plane

locals {
  flex_control_plane_extra_execution_role_statements = local.runtime.otel_exporter_headers != "" ? [
    {
      Effect = "Allow"
      Action = [
        "ssm:GetParameters",
      ]
      Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/${var.stack_name}/secrets/otel-exporter-headers"
    },
  ] : []

  flex_control_plane_extra_policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "ce:GetCostAndUsage",
        "ce:UpdateCostAllocationTagsStatus",
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricData",
        "cloudwatch:DescribeAlarms",
        "cloudtrail:LookupEvents",
        "sns:ListSubscriptionsByTopic",
      ]
      Resource = "*"
    },
    {
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:DeleteParameter",
        "ssm:DeleteParameters",
      ]
      Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/${var.stack_name}/*"
    },
    {
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
      ]
      Resource = compact([
        aws_secretsmanager_secret.runs_on_stack_config.arn,
        aws_secretsmanager_secret.runs_on_github_apps.arn,
      ])
    },
    {
      Effect = "Allow"
      Action = [
        "sns:Publish",
      ]
      Resource = module.alerts.topic_arn
    },
    {
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
      ]
      Resource = [
        aws_sqs_queue.webhooks.arn,
        aws_sqs_queue.system.arn,
        aws_sqs_queue.events.arn,
        aws_sqs_queue.webhooks_dead_letter.arn,
        aws_sqs_queue.system_dead_letter.arn,
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
      ]
      Resource = aws_dynamodb_table.locks.arn
    },
    {
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:BatchGetItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan",
      ]
      Resource = [
        aws_dynamodb_table.workflow_jobs.arn,
        "${aws_dynamodb_table.workflow_jobs.arn}/index/*",
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:${local.worker_log_group_name}:*"
    },
  ]
}

module "runtime" {
  source = "../runtime"

  region     = var.region
  account_id = var.account_id
  stack_name = var.stack_name

  cluster_name                    = var.stack_name
  service_name                    = "flexd"
  task_definition_family          = "${var.stack_name}-flexd"
  execution_role_name             = "${var.stack_name}-flex-execution-role"
  task_role_name                  = "${var.stack_name}-flex-role"
  task_policy_name                = "RunsOnFlexPermissions"
  runner_instance_role_arn        = var.compute.runner_iam.role_arn
  cache_bucket_arn                = var.extras.cache.bucket_arn
  ebs_encryption_key_id           = local.runner.ebs_encryption_key_id
  extra_execution_role_statements = local.flex_control_plane_extra_execution_role_statements
  extra_task_role_statements      = local.flex_control_plane_extra_policy_statements
  task_role_managed_policy_arns   = compact([local.runtime.custom_policy_arn])
  log_group_name                  = local.worker_log_group_name
  log_retention_days              = 14
  cpu                             = local.app_size_config.cpu
  memory                          = local.app_size_config.memory
  desired_count                   = local.runtime.maintenance_mode ? 0 : 1
  capacity_provider               = local.runtime.capacity_provider
  force_new_deployment            = local.runtime.force_new_deployment
  assign_public_ip                = local.runtime.private_mode == "false"
  security_group_ids              = var.network.security_group_ids
  subnet_ids                      = local.runtime.private_mode == "false" ? var.network.public_subnet_ids : var.network.private_subnet_ids
  tags                            = local.common_tags
  container_definitions = [
    {
      name        = "flexd"
      image       = local.runtime.ecr_repository_url != "" ? local.runtime.ecr_repository_url : local.runtime.image
      essential   = true
      entryPoint  = ["/app/dist/flexd"]
      stopTimeout = 30
      environment = [
        for key, value in merge(
          local.base_env_vars,
          {
            RUNS_ON_GITHUB_APPS_SECRET_ARN = aws_secretsmanager_secret.runs_on_github_apps.arn
          },
          ) : {
          name  = key
          value = value
        }
      ]
      secrets = concat(
        local.runtime.otel_exporter_headers != "" ? [
          {
            name      = "OTEL_EXPORTER_OTLP_HEADERS"
            valueFrom = aws_ssm_parameter.otel_exporter_headers[0].arn
          }
        ] : [],
      )
      healthCheck = {
        command     = ["CMD", "/app/dist/healthprobe"]
        interval    = 5
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.worker_log_group_name
          awslogs-region        = var.region
          awslogs-stream-prefix = "flexd"
        }
      }
    },
  ]

  depends_on = [
    aws_lambda_invocation.stack_config_materializer,
  ]
}

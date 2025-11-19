# modules/core/apprunner.tf
# App Runner service for RunsOn core module

###########################
# App Runner Auto Scaling Configuration
###########################

resource "aws_apprunner_auto_scaling_configuration_version" "this" {
  auto_scaling_configuration_name = "${var.stack_name}-autoscaling"
  max_concurrency                 = 100
  max_size                        = 25
  min_size                        = 1

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-autoscaling"
      Environment = var.environment
    }
  )
}

###########################
# App Runner VPC Connector (for private networking)
###########################

resource "aws_apprunner_vpc_connector" "this" {
  count = var.private_mode != "false" ? 1 : 0

  vpc_connector_name = "${var.stack_name}-vpc-connector"
  subnets            = var.private_subnet_ids
  security_groups    = var.security_group_ids

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-vpc-connector"
      Environment = var.environment
    }
  )
}

###########################
# App Runner IAM Role
###########################

resource "aws_iam_role" "apprunner" {
  name = "${var.stack_name}-apprunner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "tasks.apprunner.amazonaws.com",
            "build.apprunner.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-apprunner-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr" {
  role       = aws_iam_role.apprunner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# App Runner service policy
resource "aws_iam_role_policy" "apprunner_permissions" {
  name = "AppRunnerPermissions"
  role = aws_iam_role.apprunner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeImages",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeTags",
          "ec2:CreateTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:RequestSpotInstances",
          "ec2:CancelSpotInstanceRequests"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStacks",
          "cloudformation:GetTemplate"
        ]
        Resource = "arn:aws:cloudformation:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = var.ec2_instance_role_arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetInstanceProfile"
        ]
        Resource = [
          var.ec2_instance_role_arn,
          var.ec2_instance_profile_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.config_bucket_arn,
          "${var.config_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.cache_bucket_arn,
          "${var.cache_bucket_arn}/runners/*",
          "${var.cache_bucket_arn}/agents/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.main.arn,
          aws_sqs_queue.jobs.arn,
          aws_sqs_queue.github.arn,
          aws_sqs_queue.pool.arn,
          aws_sqs_queue.housekeeping.arn,
          aws_sqs_queue.termination.arn,
          aws_sqs_queue.events.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.locks.arn,
          aws_dynamodb_table.workflow_jobs.arn,
          "${aws_dynamodb_table.workflow_jobs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "RunsOn"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:UpdateCostAllocationTagsStatus",
          "cloudtrail:LookupEvents",
          "cloudwatch:GetMetricData",
          "cloudwatch:DescribeAlarms",
          "sns:ListSubscriptionsByTopic",
          "ec2:DescribeRouteTables",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "spot.amazonaws.com"
          }
        }
      }
    ]
  })
}

###########################
# App Runner Service
###########################

resource "aws_apprunner_service" "this" {
  service_name = var.stack_name

  instance_configuration {
    cpu               = var.app_cpu
    memory            = var.app_memory
    instance_role_arn = aws_iam_role.apprunner.arn
  }

  network_configuration {
    egress_configuration {
      egress_type       = var.private_mode != "false" ? "VPC" : "DEFAULT"
      vpc_connector_arn = var.private_mode != "false" ? aws_apprunner_vpc_connector.this[0].arn : null
    }

    ingress_configuration {
      is_publicly_accessible = true
    }

    ip_address_type = "IPV4"
  }

  health_check_configuration {
    path                = "/ping"
    protocol            = "HTTP"
    healthy_threshold   = 1
    unhealthy_threshold = 10
    interval            = 3
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.this.arn

  source_configuration {
    image_repository {
      image_configuration {
        port = "8080"

        runtime_environment_variables = {
          RUNS_ON_AWS_ACCOUNT_ID                    = data.aws_caller_identity.current.account_id
          RUNS_ON_ENV                               = var.environment
          RUNS_ON_COST_ALLOCATION_TAG               = var.cost_allocation_tag
          RUNS_ON_STACK_NAME                        = var.stack_name
          RUNS_ON_LOCKS_TABLE                       = aws_dynamodb_table.locks.name
          RUNS_ON_WORKFLOW_JOBS_TABLE               = aws_dynamodb_table.workflow_jobs.name
          RUNS_ON_NETWORKING_STACK                  = "external"
          RUNS_ON_GITHUB_ORGANIZATION               = var.github_organization
          RUNS_ON_APP_TAG                           = var.app_tag
          RUNS_ON_BOOTSTRAP_TAG                     = var.bootstrap_tag
          RUNS_ON_LICENSE_KEY                       = var.license_key
          RUNS_ON_RUNNER_CUSTOM_TAGS                = join(",", var.runner_custom_tags)
          RUNS_ON_BUCKET_CONFIG                     = var.config_bucket_name
          RUNS_ON_BUCKET_CACHE                      = var.cache_bucket_name
          RUNS_ON_VPC_ID                            = var.vpc_id
          RUNS_ON_SECURITY_GROUP_ID                 = join(",", var.security_group_ids)
          RUNS_ON_INSTANCE_PROFILE_ARN              = var.ec2_instance_profile_arn
          RUNS_ON_INSTANCE_ROLE_NAME                = var.ec2_instance_role_name
          RUNS_ON_TOPIC_ARN                         = aws_sns_topic.alerts.arn
          RUNS_ON_REGION                            = data.aws_region.current.name
          RUNS_ON_SSH_ALLOWED                       = var.ssh_allowed ? "true" : "false"
          RUNS_ON_APP_EC2_QUEUE_SIZE                = tostring(var.ec2_queue_size)
          RUNS_ON_EBS_ENCRYPTION_KEY                = var.ebs_encryption_key_id
          RUNS_ON_APP_GITHUB_API_STRATEGY           = var.github_api_strategy
          RUNS_ON_PUBLIC_SUBNET_IDS                 = join(",", var.public_subnet_ids)
          RUNS_ON_PRIVATE_SUBNET_IDS                = join(",", var.private_subnet_ids)
          RUNS_ON_PRIVATE                           = var.private_mode
          RUNS_ON_DEFAULT_ADMINS                    = var.default_admins
          RUNS_ON_RUNNER_MAX_RUNTIME                = tostring(var.runner_max_runtime)
          RUNS_ON_RUNNER_CONFIG_AUTO_EXTENDS_FROM   = var.runner_config_auto_extends_from
          RUNS_ON_LAUNCH_TEMPLATE_LINUX_DEFAULT     = var.launch_template_linux_default_id
          RUNS_ON_LAUNCH_TEMPLATE_WINDOWS_DEFAULT   = var.launch_template_windows_default_id
          RUNS_ON_LAUNCH_TEMPLATE_LINUX_PRIVATE     = var.launch_template_linux_private_id != null ? var.launch_template_linux_private_id : ""
          RUNS_ON_LAUNCH_TEMPLATE_WINDOWS_PRIVATE   = var.launch_template_windows_private_id != null ? var.launch_template_windows_private_id : ""
          RUNS_ON_RUNNER_DEFAULT_DISK_SIZE          = tostring(var.runner_default_disk_size)
          RUNS_ON_RUNNER_DEFAULT_VOLUME_THROUGHPUT  = tostring(var.runner_default_volume_throughput)
          RUNS_ON_RUNNER_LARGE_DISK_SIZE            = tostring(var.runner_large_disk_size)
          RUNS_ON_RUNNER_LARGE_VOLUME_THROUGHPUT    = tostring(var.runner_large_volume_throughput)
          RUNS_ON_QUEUE                             = aws_sqs_queue.main.name
          RUNS_ON_QUEUE_POOL                        = aws_sqs_queue.pool.name
          RUNS_ON_QUEUE_HOUSEKEEPING                = aws_sqs_queue.housekeeping.name
          RUNS_ON_QUEUE_TERMINATION                 = aws_sqs_queue.termination.name
          RUNS_ON_QUEUE_EVENTS                      = aws_sqs_queue.events.name
          RUNS_ON_QUEUE_JOBS                        = aws_sqs_queue.jobs.name
          RUNS_ON_QUEUE_GITHUB                      = aws_sqs_queue.github.name
          RUNS_ON_COST_REPORTS_ENABLED              = var.enable_cost_reports ? "true" : "false"
          RUNS_ON_SERVER_PASSWORD                   = var.server_password
          RUNS_ON_SPOT_CIRCUIT_BREAKER              = var.spot_circuit_breaker
          RUNS_ON_INTEGRATION_STEP_SECURITY_API_KEY = var.integration_step_security_api_key
          RUNS_ON_GITHUB_ENTERPRISE_URL             = var.github_enterprise_url
          OTEL_EXPORTER_OTLP_ENDPOINT               = var.otel_exporter_endpoint
          OTEL_EXPORTER_OTLP_HEADERS                = var.otel_exporter_headers
          RUNS_ON_LOGGER_LEVEL                      = var.logger_level
        }
      }

      image_identifier      = var.app_image
      image_repository_type = "ECR_PUBLIC"
    }

    auto_deployments_enabled = false
  }

  tags = merge(
    local.common_tags,
    {
      Name        = var.stack_name
      Environment = var.environment
      Service     = "apprunner"
    }
  )
}

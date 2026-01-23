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
      Name = "${var.stack_name}-autoscaling"
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
      Name = "${var.stack_name}-vpc-connector"
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
            "tasks.apprunner.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-apprunner-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr" {
  role       = aws_iam_role.apprunner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# App Runner service policy
resource "aws_iam_role_policy" "apprunner_permissions" {
  name = "AppRunnerEC2Permissions"
  role = aws_iam_role.apprunner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Describe actions on "*"
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:DescribeLaunchTemplateVersions",
          "ce:GetCostAndUsage",
          "ce:UpdateCostAllocationTagsStatus",
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricData",
          "cloudwatch:DescribeAlarms",
          "cloudtrail:LookupEvents",
          "iam:GetRole",
          "sns:ListSubscriptionsByTopic"
        ]
        Resource = "*"
      },
      # iam:CreateServiceLinkedRole
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
      },
      # ec2:CreateFleet, DeleteFleets
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:DeleteFleets"
        ]
        Resource = "*"
      },
      # ec2:CreateTags, RunInstances
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:RunInstances"
        ]
        Resource = [
          "arn:aws:ec2:${var.region}::image/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:*"
        ]
      },
      # iam:PassRole, GetRole on EC2InstanceRole
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:GetRole"
        ]
        Resource = var.ec2_instance_role_arn
      },
      # SSM parameters scoped to stack
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DeleteParameter",
          "ssm:DeleteParameters"
        ]
        Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/${var.stack_name}/*"
      },
      # ec2:TerminateInstances, StopInstances, StartInstances with tag condition
      {
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances"
        ]
        Resource = "arn:aws:ec2:${var.region}:${var.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/runs-on-stack-name" = var.stack_name
          }
        }
      },
      # ec2:DeleteVolume, DeleteSnapshot with tag condition
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/runs-on-stack-name" = var.stack_name
          }
        }
      },
      # S3 config bucket: GetObject, PutObject, ListBucket
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.config_bucket_arn,
          "${var.config_bucket_arn}/*"
        ]
      },
      # S3 config bucket: DeleteObject on runs-on/db/* only
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject"
        ]
        Resource = "${var.config_bucket_arn}/runs-on/db/*"
      },
      # S3 cache bucket: PutObject only
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          var.cache_bucket_arn,
          "${var.cache_bucket_arn}/runners/*",
          "${var.cache_bucket_arn}/agents/*"
        ]
      },
      # SNS Publish
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      # SQS permissions
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.main.arn,
          aws_sqs_queue.pool.arn,
          aws_sqs_queue.housekeeping.arn,
          aws_sqs_queue.termination.arn,
          aws_sqs_queue.events.arn,
          aws_sqs_queue.jobs.arn,
          aws_sqs_queue.github.arn
        ]
      },
      # DynamoDB locks table
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.locks.arn
      },
      # DynamoDB workflow_jobs table
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.workflow_jobs.arn,
          "${aws_dynamodb_table.workflow_jobs.arn}/index/*"
        ]
      },
      # CloudWatch logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/apprunner/RunsOnService-*"
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

        # Non-sensitive environment variables
        runtime_environment_variables = local.base_env_vars

        # Sensitive environment variables fetched from SSM Parameter Store at runtime
        runtime_environment_secrets = local.sensitive_env_secrets
      }

      image_identifier      = var.app_image
      image_repository_type = "ECR_PUBLIC"
    }

    auto_deployments_enabled = false
  }

  tags = merge(
    local.common_tags,
    {
      Name               = var.stack_name
      "runs-on-resource" = "apprunner-service" # Used for resource discovery
    }
  )
}

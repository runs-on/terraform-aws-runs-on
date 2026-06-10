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
  has_ebs_encryption_key = trimspace(var.ebs_encryption_key_id) != ""
  ebs_encryption_policy_statements = concat(
    local.has_ebs_encryption_key ? [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
        ]
        Resource = data.aws_kms_key.ebs_encryption[0].arn
      },
    ] : [],
    local.has_ebs_encryption_key ? [
      {
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
        ]
        Resource = data.aws_kms_key.ebs_encryption[0].arn
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = true
          }
        }
      },
    ] : [],
  )

  shared_task_role_statements = [
    {
      Effect = "Allow"
      Action = [
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeRouteTables",
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:DescribeLaunchTemplateVersions",
      ]
      Resource = "*"
    },
    {
      Effect = "Allow"
      Action = [
        "iam:GetRole",
      ]
      Resource = var.runner_instance_role_arn
    },
    {
      Effect = "Allow"
      Action = [
        "iam:CreateServiceLinkedRole"
      ]
      Resource = "arn:aws:iam::${var.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
      Condition = {
        StringEquals = {
          "iam:AWSServiceName" = "spot.amazonaws.com"
        }
      }
    },
    {
      Effect = "Allow"
      Action = [
        "ec2:CreateFleet",
        "ec2:DeleteFleets",
      ]
      Resource = "*"
    },
    {
      Effect = "Allow"
      Action = [
        "ec2:CreateTags",
        "ec2:RunInstances",
      ]
      Resource = [
        "arn:aws:ec2:${var.region}::image/*",
        "arn:aws:ec2:${var.region}:${var.account_id}:instance/*",
        "arn:aws:ec2:${var.region}:${var.account_id}:volume/*",
        "arn:aws:ec2:${var.region}:${var.account_id}:network-interface/*",
        "arn:aws:ec2:${var.region}:${var.account_id}:security-group/*",
        "arn:aws:ec2:${var.region}:${var.account_id}:subnet/*",
        "arn:aws:ec2:${var.region}:${var.account_id}:launch-template/*",
        "arn:aws:ec2:${var.region}:${var.account_id}:key-pair/*",
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "iam:PassRole",
        "iam:GetRole",
      ]
      Resource = var.runner_instance_role_arn
    },
    {
      Effect = "Allow"
      Action = [
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
      ]
      Resource = "arn:aws:ec2:${var.region}:${var.account_id}:instance/*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/runs-on-stack-name" = var.stack_name
        }
      }
    },
    {
      Effect = "Allow"
      Action = [
        "ec2:DeleteVolume",
        "ec2:DeleteSnapshot",
      ]
      Resource = [
        "arn:aws:ec2:${var.region}:${var.account_id}:volume/*",
        "arn:aws:ec2:${var.region}::snapshot/*",
      ]
      Condition = {
        StringEquals = {
          "aws:ResourceTag/runs-on-stack-name" = var.stack_name
        }
      }
    },
    {
      Effect = "Allow"
      Action = [
        "s3:ListBucket",
      ]
      Resource = var.cache_bucket_arn
      Condition = {
        StringLike = {
          "s3:prefix" = [
            "cache",
            "cache/*",
            "agents",
            "agents/*",
            "runners",
            "runners/*",
          ]
        }
      }
    },
    {
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
      ]
      Resource = [
        "${var.cache_bucket_arn}/cache/*",
        "${var.cache_bucket_arn}/runners/*",
        "${var.cache_bucket_arn}/agents/*",
      ]
    },
  ]
}

data "aws_kms_key" "ebs_encryption" {
  count = local.has_ebs_encryption_key ? 1 : 0

  key_id = trimspace(var.ebs_encryption_key_id)
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-${var.service_name}-logs"
    }
  )
}

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  dynamic "setting" {
    for_each = var.container_insights_enabled ? [1] : []
    content {
      name  = "containerInsights"
      value = "enabled"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = [
    "FARGATE",
    "FARGATE_SPOT",
  ]
}

resource "aws_iam_role" "execution" {
  name = var.execution_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = var.execution_role_name
    }
  )
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_extra" {
  count = length(var.extra_execution_role_statements) > 0 ? 1 : 0

  name = "${var.service_name}-execution-extra"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.extra_execution_role_statements
  })
}

resource "aws_iam_role" "task" {
  name = var.task_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = var.task_role_name
    }
  )
}

resource "aws_iam_role_policy" "task" {
  name = var.task_policy_name
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.shared_task_role_statements,
      local.ebs_encryption_policy_statements,
      var.extra_task_role_statements,
    )
  })
}

resource "aws_iam_role_policy_attachment" "task_managed" {
  for_each = toset(compact(var.task_role_managed_policy_arns))

  role       = aws_iam_role.task.name
  policy_arn = each.value
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.task_definition_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode(var.container_definitions)

  tags = merge(
    var.tags,
    {
      Name = "${var.task_definition_family}-task"
    }
  )
}

resource "aws_ecs_service" "this" {
  name             = var.service_name
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = var.desired_count
  platform_version = var.platform_version
  propagate_tags   = "SERVICE"

  enable_ecs_managed_tags = true
  force_new_deployment    = var.force_new_deployment
  # Deploy workflows schedule runners immediately after Terraform returns, so
  # wait until ECS has actually rolled the control-plane task to the new version.
  wait_for_steady_state = true

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  network_configuration {
    assign_public_ip = var.assign_public_ip
    security_groups  = var.security_group_ids
    subnets          = var.subnet_ids
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-${var.service_name}"
    }
  )

  depends_on = [
    aws_ecs_cluster_capacity_providers.this,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_extra,
  ]
}

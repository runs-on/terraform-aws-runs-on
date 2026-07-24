terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.45 guarantees nodejs24.x runtime support (matches the flex/fleet products).
      version = ">= 6.45"
    }
  }
}

data "aws_region" "current" {}

# kms_key_id = "default": resolve the region's EBS default key to a key ARN
# (aws_ebs_default_kms_key may return an alias, so normalize via aws_kms_key).
data "aws_ebs_default_kms_key" "current" {
  count = (var.enabled && local.kms_use_default) ? 1 : 0
}

data "aws_kms_key" "ebs_default" {
  count  = (var.enabled && local.kms_use_default) ? 1 : 0
  key_id = data.aws_ebs_default_kms_key.current[0].key_arn
}

# kms_key_id = "aws/ebs": resolve the AWS-managed EBS key to a key ARN.
data "aws_kms_key" "aws_ebs" {
  count  = (var.enabled && local.kms_use_aws_ebs) ? 1 : 0
  key_id = "alias/aws/ebs"
}

locals {
  count               = var.enabled ? 1 : 0
  lambda_artifact_dir = "${path.module}/../../lambdas/dist"
  name                = "${var.stack_name}-${var.name_suffix}"
  region              = data.aws_region.current.region
  # IAM role names are account-global, so include the region: this module is
  # deployed once per account+region and the roles would otherwise collide.
  role_prefix  = "${local.name}-${local.region}"
  scheduler_in = jsonencode({ images = var.images, tags = var.common_tags })

  # kms_key_id accepts: "" (no explicit encryption), "default" (the region's EBS
  # default key), "aws/ebs" (the AWS-managed EBS key), or an explicit key ARN.
  kms_input       = trimspace(var.kms_key_id)
  kms_use_default = local.kms_input == "default"
  kms_use_aws_ebs = local.kms_input == "aws/ebs" || local.kms_input == "alias/aws/ebs"
  kms_explicit    = (local.kms_input != "" && !local.kms_use_default && !local.kms_use_aws_ebs) ? local.kms_input : ""

  # Resolve the chosen mode to a concrete key ARN (length-guarded for count=0).
  effective_kms_key_arn = (
    local.kms_use_default ? (length(data.aws_kms_key.ebs_default) > 0 ? data.aws_kms_key.ebs_default[0].arn : "") :
    local.kms_use_aws_ebs ? (length(data.aws_kms_key.aws_ebs) > 0 ? data.aws_kms_key.aws_ebs[0].arn : "") :
    local.kms_explicit
  )
  has_kms_key = local.effective_kms_key_arn != ""

  common_tags = merge(
    var.common_tags,
    {
      Name = local.name
    }
  )

  # KMS statements mirror runtime/main.tf:13-44 so the Lambda can encrypt copies
  # with the resolved key (decrypt-at-launch is covered by the product's existing
  # grants). Built as concat of single-element conditionals so the two
  # differently-shaped statements unify (one carries a Condition, one does not).
  kms_statements = concat(
    local.has_kms_key ? [
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
        Resource = local.effective_kms_key_arn
      },
    ] : [],
    local.has_kms_key ? [
      {
        Effect   = "Allow"
        Action   = ["kms:CreateGrant"]
        Resource = local.effective_kms_key_arn
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = true
          }
        }
      },
    ] : [],
  )
}

resource "aws_cloudwatch_log_group" "ami_sync" {
  count             = local.count
  name              = "/runs-on/${var.stack_name}/lambda/${var.name_suffix}"
  retention_in_days = var.log_retention_in_days
  tags              = local.common_tags
}

resource "aws_iam_role" "ami_sync" {
  count = local.count
  name  = "${local.role_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ami_sync_logs" {
  count = local.count
  name  = "RunsOnAmiSyncLogPermissions"
  role  = aws_iam_role.ami_sync[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.ami_sync[0].arn}:*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "ami_sync" {
  count = local.count
  name  = "RunsOnAmiSyncPermissions"
  role  = aws_iam_role.ami_sync[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          # Describe* and CopyImage cannot be resource-scoped.
          Effect   = "Allow"
          Action   = ["ec2:DescribeImages", "ec2:DescribeSnapshots", "ec2:CopyImage"]
          Resource = "*"
        },
        {
          # Tagging is only ever needed as part of CopyImage tag-on-create. The
          # ec2:CreateAction condition blocks arbitrary post-hoc tagging, which
          # could otherwise stamp runs-on-stack-name onto unrelated self-owned
          # images and satisfy the DeregisterImage/DeleteSnapshot conditions below.
          Effect = "Allow"
          Action = ["ec2:CreateTags"]
          Resource = [
            "arn:aws:ec2:${local.region}::image/*",
            "arn:aws:ec2:${local.region}::snapshot/*",
          ]
          Condition = {
            StringEquals = {
              "ec2:CreateAction" = "CopyImage"
            }
          }
        },
        {
          # DeregisterImage scoped to images this stack tagged at create time, so
          # the role can never deregister golden/manually managed AMIs.
          Effect   = "Allow"
          Action   = ["ec2:DeregisterImage"]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:ResourceTag/runs-on-stack-name" = var.stack_name
            }
          }
        },
        {
          # DeleteSnapshot scoped to snapshots this stack tagged at create time.
          Effect   = "Allow"
          Action   = ["ec2:DeleteSnapshot"]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:ResourceTag/runs-on-stack-name" = var.stack_name
            }
          }
        },
      ],
      local.kms_statements,
    )
  })
}

resource "aws_lambda_function" "ami_sync" {
  count         = local.count
  function_name = local.name
  role          = aws_iam_role.ami_sync[0].arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  architectures = ["arm64"]
  timeout       = 900
  memory_size   = 256

  filename         = "${local.lambda_artifact_dir}/ami-sync.zip"
  source_code_hash = filebase64sha256("${local.lambda_artifact_dir}/ami-sync.zip")

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.ami_sync[0].name
  }

  environment {
    variables = {
      RUNS_ON_STACK_NAME             = var.stack_name
      RUNS_ON_AMI_SYNC_SOURCE_REGION = var.source_region
      RUNS_ON_AMI_SOURCE_OWNER       = var.source_owner
      RUNS_ON_AMI_SYNC_RETENTION     = tostring(var.retention)
      RUNS_ON_KMS_KEY_ID             = local.effective_kms_key_arn
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.ami_sync_logs]
}

resource "aws_iam_role" "scheduler" {
  count = local.count
  name  = "${local.role_prefix}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.count
  name  = "InvokeAmiSync"
  role  = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.ami_sync[0].arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "ami_sync" {
  count                        = local.count
  name                         = local.name
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.ami_sync[0].arn
    role_arn = aws_iam_role.scheduler[0].arn

    retry_policy {
      maximum_retry_attempts = 0
    }

    input = local.scheduler_in
  }
}

# Seed invocation so the first copy happens at apply time. aws_lambda_invocation is
# CREATE_ONLY by default, so re-invoke whenever the sync inputs or function code
# change (source_region/source_owner/kms_key_id arrive via env, not `input`).
resource "aws_lambda_invocation" "ami_sync_seed" {
  count         = local.count
  function_name = aws_lambda_function.ami_sync[0].function_name
  input         = local.scheduler_in

  triggers = {
    input = local.scheduler_in
    config = jsonencode({
      source_region = var.source_region
      source_owner  = var.source_owner
      kms_key_id    = var.kms_key_id
      retention     = var.retention
    })
    code = aws_lambda_function.ami_sync[0].source_code_hash
  }

  depends_on = [aws_iam_role_policy.ami_sync]
}

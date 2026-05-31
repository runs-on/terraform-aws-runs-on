# modules/compute/iam.tf
# IAM roles and policies for EC2 instances

###########################
# EC2 Instance IAM Role
###########################

resource "aws_iam_role" "ec2_instance" {
  name = "${var.stack_name}-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  permissions_boundary = var.permission_boundary_arn != "" ? var.permission_boundary_arn : null

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ec2-instance-role"
    }
  )
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_public" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicFullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_custom" {
  count = trimspace(var.runner_custom_policy_arn) != "" ? 1 : 0

  role       = aws_iam_role.ec2_instance.name
  policy_arn = var.runner_custom_policy_arn
}

# Inline policies for EC2 instances
resource "aws_iam_role_policy" "ec2_read_only" {
  name = "ReadOnly"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_create_tags" {
  name = "CreateTags"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:TagKeys" = [
              "runs-on-pool-name",
              "runs-on-pool-spec-hash",
              "runs-on-pool-standby-type",
              "runs-on-pool-detached-at",
              "runs-on-pool-lease-state",
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ARN" = "$${ec2:SourceInstanceARN}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_create_tags_volumes" {
  name = "CreateTagsOnVolumesAndSnapshots"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:aws:ec2:${var.region}:*:snapshot/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_cloudwatch_logs" {
  name = "SendLogs"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:${local.log_group_name}",
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:${local.log_group_name}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_cloudwatch_metrics" {
  name = "PutMetrics"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = [
              "RunsOn/Runners",
              "CWAgent"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_get_metrics" {
  name = "GetMetrics"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_s3_access" {
  name = "EC2AccessS3BucketPolicy"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
        ]
        Resource = [
          var.extras.cache.bucket_arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
        ]
        Resource = [
          var.extras.cache.bucket_arn,
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "cache",
              "cache/*",
              "agents",
              "agents/*",
              "runners/$${aws:userid}/",
              "runners/$${aws:userid}/*",
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "${var.extras.cache.bucket_arn}/cache/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${var.extras.cache.bucket_arn}/runners/$${aws:userid}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${var.extras.cache.bucket_arn}/agents/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_snapshot_describe" {
  name = "VolumeSnapshotDescribe"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_snapshot_create" {
  name = "VolumeSnapshotCreate"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:CreateSnapshot"
        ]
        Resource = [
          "arn:aws:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:aws:ec2:${var.region}::snapshot/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_snapshot_lifecycle" {
  name = "VolumeSnapshotLifecycle"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot"
        ]
        Resource = [
          "arn:aws:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:aws:ec2:${var.region}::snapshot/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:instance/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/runs-on-stack-name" = var.stack_name
          }
        }
      }
    ]
  })
}

# EFS access policy (conditional)
resource "aws_iam_role_policy" "ec2_efs_access" {
  count = var.extras.efs.enabled ? 1 : 0

  name = "EfsMountAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeSubnets",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECR access policy (conditional)
resource "aws_iam_role_policy" "ec2_ecr_access" {
  count = var.extras.ecr.enabled ? 1 : 0

  name = "EphemeralRegistryAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = var.extras.ecr.repository_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_ecr_pull_through_cache_access" {
  count = var.extras.pull_through_cache.enabled ? 1 : 0

  name = "EcrPullThroughCacheAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:CreateRepository",
          "ecr:BatchImportUpstreamImage"
        ]
        Resource = distinct(flatten([
          for rule in values(var.extras.pull_through_cache.rules) :
          rule.ecr_repository_prefix == "ROOT" ?
          ["arn:aws:ecr:${var.region}:${var.account_id}:repository/*"] :
          ["arn:aws:ecr:${var.region}:${var.account_id}:repository/${rule.ecr_repository_prefix}/*"]
        ]))
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_bedrock_access" {
  count = var.enable_bedrock ? 1 : 0

  name = "BedrockAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = [
          "arn:aws:bedrock:*:*:foundation-model/*",
          "arn:aws:bedrock:*:*:inference-profile/*",
          "arn:aws:bedrock:*:*:application-inference-profile/*"
        ]
      }
    ]
  })
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.stack_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance.name

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ec2-instance-profile"
    }
  )
}

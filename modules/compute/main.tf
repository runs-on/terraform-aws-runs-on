# modules/compute/main.tf
# Compute module for RunsOn - EC2 launch templates and IAM roles

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "opentofu"
      Module    = "runs-on-compute"
    }
  )
}

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

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
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
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
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
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/${var.cost_allocation_tag}" = var.stack_name
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
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*"
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
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_name}",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_name}:*"
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
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = [
              "RunsOn",
              "AWS/EC2",
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
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_s3_access" {
  name = "S3Access"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads"
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
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${var.cache_bucket_arn}/cache/*"
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
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ebs:ListSnapshotBlocks"
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
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ebs:StartSnapshot"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*"
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
          "ec2:DeleteSnapshot",
          "ec2:ModifySnapshotAttribute",
          "ebs:CompleteSnapshot",
          "ebs:PutSnapshotBlock"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}::snapshot/*",
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/${var.cost_allocation_tag}" = var.stack_name
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_detailed_monitoring" {
  name = "EnableDetailedMonitoring"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:MonitorInstances",
          "ec2:UnmonitorInstances"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/${var.cost_allocation_tag}" = var.stack_name
          }
        }
      }
    ]
  })
}

# EFS access policy (conditional)
resource "aws_iam_role_policy" "ec2_efs_access" {
  count = var.efs_file_system_id != "" ? 1 : 0

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
          "elasticfilesystem:ClientRootAccess",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeAccessPoints",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECR access policy (conditional)
resource "aws_iam_role_policy" "ec2_ecr_access" {
  count = var.ephemeral_registry_arn != "" ? 1 : 0

  name = "EphemeralRegistryAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchDeleteImage"
        ]
        Resource = var.ephemeral_registry_arn
      }
    ]
  })
}

# Custom policy attachment (optional)
resource "aws_iam_role_policy" "ec2_custom_policy" {
  count = var.custom_policy_json != "" ? 1 : 0

  name   = "CustomPolicy"
  role   = aws_iam_role.ec2_instance.id
  policy = var.custom_policy_json
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

###########################
# EC2 Launch Templates
###########################

# Linux Default (Public) Launch Template
resource "aws_launch_template" "linux_default" {
  name_prefix   = "${var.stack_name}-linux-default-"
  image_id      = var.linux_ami_id
  instance_type = "t3.medium" # Placeholder, will be overridden at launch

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = var.detailed_monitoring_enabled
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.runner_default_disk_size
      volume_type           = "gp3"
      throughput            = var.runner_default_volume_throughput
      delete_on_termination = true
      encrypted             = var.ebs_encryption_enabled
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  user_data = base64encode(templatefile("${path.module}/user-data-linux.sh", {
    app_tag                = var.app_tag
    bootstrap_tag          = var.bootstrap_tag
    efs_file_system_id     = var.efs_file_system_id
    ephemeral_registry_uri = var.ephemeral_registry_uri
    config_bucket          = var.config_bucket_name
    cache_bucket           = var.cache_bucket_name
    region                 = data.aws_region.current.name
    log_group              = var.log_group_name
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-linux-default"
      LaunchType  = "linux-default"
      NetworkType = "public"
    }
  )
}

# Windows Default (Public) Launch Template
resource "aws_launch_template" "windows_default" {
  name_prefix   = "${var.stack_name}-windows-default-"
  image_id      = var.windows_ami_id
  instance_type = "t3.large" # Placeholder

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = var.detailed_monitoring_enabled
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.runner_default_disk_size
      volume_type           = "gp3"
      throughput            = var.runner_default_volume_throughput
      delete_on_termination = true
      encrypted             = var.ebs_encryption_enabled
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  user_data = base64encode(templatefile("${path.module}/user-data-windows.ps1", {
    app_tag                = var.app_tag
    bootstrap_tag          = var.bootstrap_tag
    efs_file_system_id     = var.efs_file_system_id
    ephemeral_registry_uri = var.ephemeral_registry_uri
    config_bucket          = var.config_bucket_name
    cache_bucket           = var.cache_bucket_name
    region                 = data.aws_region.current.name
    log_group              = var.log_group_name
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-windows-default"
      LaunchType  = "windows-default"
      NetworkType = "public"
    }
  )
}

# Linux Private Launch Template
resource "aws_launch_template" "linux_private" {
  count = var.private_networking_enabled ? 1 : 0

  name_prefix   = "${var.stack_name}-linux-private-"
  image_id      = var.linux_ami_id
  instance_type = "t3.medium"

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = var.detailed_monitoring_enabled
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.runner_default_disk_size
      volume_type           = "gp3"
      throughput            = var.runner_default_volume_throughput
      delete_on_termination = true
      encrypted             = var.ebs_encryption_enabled
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  user_data = base64encode(templatefile("${path.module}/user-data-linux.sh", {
    app_tag                = var.app_tag
    bootstrap_tag          = var.bootstrap_tag
    efs_file_system_id     = var.efs_file_system_id
    ephemeral_registry_uri = var.ephemeral_registry_uri
    config_bucket          = var.config_bucket_name
    cache_bucket           = var.cache_bucket_name
    region                 = data.aws_region.current.name
    log_group              = var.log_group_name
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-linux-private"
      LaunchType  = "linux-private"
      NetworkType = "private"
    }
  )
}

# Windows Private Launch Template
resource "aws_launch_template" "windows_private" {
  count = var.private_networking_enabled ? 1 : 0

  name_prefix   = "${var.stack_name}-windows-private-"
  image_id      = var.windows_ami_id
  instance_type = "t3.large"

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = var.detailed_monitoring_enabled
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.runner_default_disk_size
      volume_type           = "gp3"
      throughput            = var.runner_default_volume_throughput
      delete_on_termination = true
      encrypted             = var.ebs_encryption_enabled
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      local.common_tags,
      {
        (var.cost_allocation_tag) = var.stack_name
      }
    )
  }

  user_data = base64encode(templatefile("${path.module}/user-data-windows.ps1", {
    app_tag                = var.app_tag
    bootstrap_tag          = var.bootstrap_tag
    efs_file_system_id     = var.efs_file_system_id
    ephemeral_registry_uri = var.ephemeral_registry_uri
    config_bucket          = var.config_bucket_name
    cache_bucket           = var.cache_bucket_name
    region                 = data.aws_region.current.name
    log_group              = var.log_group_name
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-windows-private"
      LaunchType  = "windows-private"
      NetworkType = "private"
    }
  )
}

###########################
# CloudWatch Log Group
###########################

resource "aws_cloudwatch_log_group" "ec2_instances" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ec2-logs"
    }
  )
}

###########################
# EC2 Resource Group
###########################

resource "aws_resourcegroups_group" "ec2_instances" {
  name        = "${var.stack_name}-ec2-instances"
  description = "Resource group for RunsOn EC2 instances in ${var.stack_name}"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::EC2::Instance"]
      TagFilters = [
        {
          Key    = var.cost_allocation_tag
          Values = [var.stack_name]
        }
      ]
    })
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ec2-instances"
    }
  )
}

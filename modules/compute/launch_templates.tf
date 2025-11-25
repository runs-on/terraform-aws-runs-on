# modules/compute/launch_templates.tf
# EC2 Launch Templates for RunsOn runners

###########################
# EC2 Launch Templates
###########################

# Linux Default (Public) Launch Template
resource "aws_launch_template" "linux_default" {
  name = "${var.stack_name}-linux-default"
  image_id      = var.linux_ami_id
  instance_type = "t3.medium" # Placeholder, will be overridden at launch

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

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
    app_debug              = var.app_debug ? "true" : "false"
    runner_max_runtime     = var.runner_max_runtime
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-linux-default"
      LaunchType  = "linux-default"
      NetworkType = "public"
      Environment = var.environment
    }
  )
}

# Windows Default (Public) Launch Template
resource "aws_launch_template" "windows_default" {
  name = "${var.stack_name}-windows-default"
  image_id      = var.windows_ami_id
  instance_type = "t3.large" # Placeholder

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

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
    app_debug              = var.app_debug ? "true" : "false"
    runner_max_runtime     = var.runner_max_runtime
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-windows-default"
      LaunchType  = "windows-default"
      NetworkType = "public"
      Environment = var.environment
    }
  )
}

# Linux Private Launch Template
resource "aws_launch_template" "linux_private" {
  name = "${var.stack_name}-linux-private"
  image_id      = var.linux_ami_id
  instance_type = "t3.medium"

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

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
    app_debug              = var.app_debug ? "true" : "false"
    runner_max_runtime     = var.runner_max_runtime
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-linux-private"
      LaunchType  = "linux-private"
      NetworkType = "private"
      Environment = var.environment
    }
  )
}

# Windows Private Launch Template
resource "aws_launch_template" "windows_private" {
  name = "${var.stack_name}-windows-private"
  image_id      = var.windows_ami_id
  instance_type = "t3.large"

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

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
    app_debug              = var.app_debug ? "true" : "false"
    runner_max_runtime     = var.runner_max_runtime
  }))

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-windows-private"
      LaunchType  = "windows-private"
      NetworkType = "private"
      Environment = var.environment
    }
  )
}

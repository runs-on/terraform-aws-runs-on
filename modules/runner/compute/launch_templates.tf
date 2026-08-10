# modules/compute/launch_templates.tf
# EC2 Launch Templates for RunsOn runners

locals {
  nested_launch_template_instance_type = "c8i.large"
  efs_file_system_id                   = try(var.extras.efs.enabled, false) ? trimspace(var.extras.efs.file_system_id) : ""
  ecr_repository_url                   = try(var.extras.ecr.enabled, false) ? trimspace(var.extras.ecr.repository_url) : ""
  ecr_pull_through_cache_registry_url  = try(var.extras.pull_through_cache.enabled, false) ? trimspace(var.extras.pull_through_cache.registry_url) : ""

  linux_user_data_vars = {
    RunnerMaxRuntime    = var.runner_max_runtime
    EC2InstanceLogGroup = local.log_group_name
    Region              = var.region
    S3BucketCache       = var.extras.cache.bucket_name
    RoleId              = aws_iam_role.ec2_instance.unique_id
    BootstrapTag        = var.bootstrap_tag
    AppTag              = var.app_tag
    AgentS3Bucket       = "s3://${var.extras.cache.bucket_name}/agents/${var.app_tag}"
    EfsEnvLine          = local.efs_file_system_id != "" ? "RUNS_ON_EFS_ID=\"${local.efs_file_system_id}\"" : ""
    EphemeralRegistryEnvLine = join("\n", compact([
      local.ecr_repository_url != "" ? "RUNS_ON_ECR_CACHE=\"${local.ecr_repository_url}\"" : "",
      local.ecr_pull_through_cache_registry_url != "" ? "RUNS_ON_ECR_PULL_THROUGH_CACHE=\"${local.ecr_pull_through_cache_registry_url}\"" : "",
      local.ecr_pull_through_cache_registry_url != "" && var.extras.pull_through_cache.docker_hub_transparent ? "RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_MIRROR=\"true\"" : "",
    ]))
  }

  windows_user_data_vars = {
    RunnerMaxRuntime    = var.runner_max_runtime
    EC2InstanceLogGroup = local.log_group_name
    Region              = var.region
    S3BucketCache       = var.extras.cache.bucket_name
    BootstrapTag        = var.bootstrap_tag
    AgentS3Bucket       = "s3://${var.extras.cache.bucket_name}/agents/${var.app_tag}"
    EfsEnvLine          = local.efs_file_system_id != "" ? "$env:RUNS_ON_EFS_ID = \"${local.efs_file_system_id}\"" : ""
    EphemeralRegistryEnvLine = join("\n", compact([
      local.ecr_repository_url != "" ? "$env:RUNS_ON_ECR_CACHE = \"${local.ecr_repository_url}\"" : "",
      local.ecr_pull_through_cache_registry_url != "" ? "$env:RUNS_ON_ECR_PULL_THROUGH_CACHE = \"${local.ecr_pull_through_cache_registry_url}\"" : "",
      local.ecr_pull_through_cache_registry_url != "" && var.extras.pull_through_cache.docker_hub_transparent ? "$env:RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_MIRROR = \"true\"" : "",
    ]))
  }
}

###########################
# EC2 Launch Templates
###########################

# Linux Default (Public) Launch Template
resource "aws_launch_template" "linux_default" {
  name          = "${var.stack_name}-linux-default"
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

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/linux-bootstrap.sh.tmpl", local.linux_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-linux-default"
    }
  )
}

resource "aws_launch_template" "linux_default_nested" {
  name          = "${var.stack_name}-linux-default-nested"
  instance_type = local.nested_launch_template_instance_type

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

  cpu_options {
    nested_virtualization = "enabled"
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/linux-bootstrap.sh.tmpl", local.linux_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-linux-default-nested"
    }
  )
}

# Windows Default (Public) Launch Template
resource "aws_launch_template" "windows_default" {
  name          = "${var.stack_name}-windows-default"
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

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/windows-bootstrap.ps1.tmpl", local.windows_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-windows-default"
    }
  )
}

resource "aws_launch_template" "windows_default_nested" {
  name          = "${var.stack_name}-windows-default-nested"
  instance_type = local.nested_launch_template_instance_type

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

  cpu_options {
    nested_virtualization = "enabled"
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/windows-bootstrap.ps1.tmpl", local.windows_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-windows-default-nested"
    }
  )
}

# Linux Private Launch Template
resource "aws_launch_template" "linux_private" {
  name          = "${var.stack_name}-linux-private"
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

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/linux-bootstrap.sh.tmpl", local.linux_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-linux-private"
    }
  )
}

resource "aws_launch_template" "linux_private_nested" {
  name          = "${var.stack_name}-linux-private-nested"
  instance_type = local.nested_launch_template_instance_type

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

  cpu_options {
    nested_virtualization = "enabled"
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/linux-bootstrap.sh.tmpl", local.linux_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-linux-private-nested"
    }
  )
}

# Windows Private Launch Template
resource "aws_launch_template" "windows_private" {
  name          = "${var.stack_name}-windows-private"
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

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/windows-bootstrap.ps1.tmpl", local.windows_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-windows-private"
    }
  )
}

resource "aws_launch_template" "windows_private_nested" {
  name          = "${var.stack_name}-windows-private-nested"
  instance_type = local.nested_launch_template_instance_type

  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"

  cpu_options {
    nested_virtualization = "enabled"
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    device_index                = 0
    security_groups             = var.network.security_group_ids
    ipv6_address_count          = var.ipv6_enabled ? 1 : 0
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.common_tags
  }

  user_data = base64encode(templatefile("${path.module}/user-data/windows-bootstrap.ps1.tmpl", local.windows_user_data_vars))

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-windows-private-nested"
    }
  )
}

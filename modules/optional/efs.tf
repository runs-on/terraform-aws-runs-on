# modules/optional/efs.tf
# EFS resources for RunsOn optional module

###########################
# EFS File System
###########################

# EFS with prevent_destroy enabled (for production)
resource "aws_efs_file_system" "this_protected" {
  count = var.enable_efs && var.prevent_destroy ? 1 : 0

  encrypted = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-efs"
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

# EFS without prevent_destroy (for non-production/testing)
resource "aws_efs_file_system" "this_unprotected" {
  count = var.enable_efs && !var.prevent_destroy ? 1 : 0

  encrypted = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-efs"
    }
  )
}

locals {
  efs_file_system_id = var.enable_efs ? (
    var.prevent_destroy ? aws_efs_file_system.this_protected[0].id : aws_efs_file_system.this_unprotected[0].id
  ) : ""
}

###########################
# EFS Security Group
###########################

resource "aws_security_group" "efs" {
  count = var.enable_efs ? 1 : 0

  name        = "${var.stack_name}-efs-sg"
  description = "Security group for RunsOn EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from runner security group"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.security_group_ids
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-efs-sg"
    }
  )
}

###########################
# EFS Mount Targets
###########################

resource "aws_efs_mount_target" "az1" {
  count = var.enable_efs ? 1 : 0

  file_system_id  = local.efs_file_system_id
  subnet_id       = var.public_subnet_ids[0]
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_efs_mount_target" "az2" {
  count = var.enable_efs && length(var.public_subnet_ids) > 1 ? 1 : 0

  file_system_id  = local.efs_file_system_id
  subnet_id       = var.public_subnet_ids[1]
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_efs_mount_target" "az3" {
  count = var.enable_efs && length(var.public_subnet_ids) > 2 ? 1 : 0

  file_system_id  = local.efs_file_system_id
  subnet_id       = var.public_subnet_ids[2]
  security_groups = [aws_security_group.efs[0].id]
}

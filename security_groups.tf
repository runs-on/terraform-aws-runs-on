# security_groups.tf
# Security group for runner instances (created when security_group_ids is empty)

locals {
  # Determine if we need to create a security group
  create_security_group = length(var.security_group_ids) == 0

  # Use created security group if we created one, otherwise use provided IDs
  effective_security_group_ids = local.create_security_group ? [aws_security_group.runners[0].id] : var.security_group_ids
}

resource "aws_security_group" "runners" {
  count = local.create_security_group ? 1 : 0

  name_prefix = "${var.stack_name}-runners-"
  description = "Security group for RunsOn runner instances"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-runners"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# SSH ingress rule (conditional on ssh_allowed)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = local.create_security_group && var.ssh_allowed ? 1 : 0

  security_group_id = aws_security_group.runners[0].id
  description       = "SSH access for runners"

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_ipv4   = var.ssh_cidr_range

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ssh-ingress"
    }
  )
}

# Egress rule - Allow all outbound IPv4 traffic
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  count = local.create_security_group ? 1 : 0

  security_group_id = aws_security_group.runners[0].id
  description       = "Allow all outbound IPv4 traffic"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-egress-ipv4"
    }
  )
}

# Egress rule - Allow all outbound IPv6 traffic
resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  count = local.create_security_group ? 1 : 0

  security_group_id = aws_security_group.runners[0].id
  description       = "Allow all outbound IPv6 traffic"

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-egress-ipv6"
    }
  )
}

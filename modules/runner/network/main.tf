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
  create_security_group        = length(var.security_group_ids) == 0
  effective_security_group_ids = local.create_security_group ? [aws_security_group.runners[0].id] : var.security_group_ids
}

resource "aws_security_group" "runners" {
  count = local.create_security_group ? 1 : 0

  name_prefix = "${var.stack_name}-runners-"
  description = "Security group for RunsOn Flex and Fleet runners"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-runners"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = local.create_security_group && var.ssh_allowed ? 1 : 0

  security_group_id = aws_security_group.runners[0].id
  description       = "SSH access for runners"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ssh_cidr_range

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-ssh-ingress"
    }
  )
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  count = local.create_security_group ? 1 : 0

  security_group_id = aws_security_group.runners[0].id
  description       = "Allow all outbound IPv4 traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-egress-ipv4"
    }
  )
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  count = local.create_security_group ? 1 : 0

  security_group_id = aws_security_group.runners[0].id
  description       = "Allow all outbound IPv6 traffic"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-egress-ipv6"
    }
  )
}

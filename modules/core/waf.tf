# modules/core/waf.tf
# AWS WAF configuration for App Runner service

###########################
# GitHub IP Ranges (via public API)
###########################

data "http" "github_meta" {
  count = var.enable_waf ? 1 : 0
  url   = "https://api.github.com/meta"

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  # Parse GitHub meta API response
  github_meta = var.enable_waf ? jsondecode(data.http.github_meta[0].response_body) : null

  # GitHub hooks array contains both IPv4 and IPv6 mixed - separate them
  # IPv6 addresses contain ":", IPv4 addresses don't
  github_hooks_ipv4 = var.enable_waf ? [
    for cidr in local.github_meta.hooks : cidr if !can(regex(":", cidr))
  ] : []
  github_hooks_ipv6 = var.enable_waf ? [
    for cidr in local.github_meta.hooks : cidr if can(regex(":", cidr))
  ] : []

  # Combine GitHub hooks IPs with custom allowed ranges (IPv4)
  waf_allowed_cidrs_ipv4 = var.enable_waf ? concat(
    local.github_hooks_ipv4,
    var.waf_allowed_ipv4_cidrs
  ) : []

  # Combine GitHub hooks IPs with custom allowed ranges (IPv6)
  waf_allowed_cidrs_ipv6 = var.enable_waf ? concat(
    local.github_hooks_ipv6,
    var.waf_allowed_ipv6_cidrs
  ) : []
}

###########################
# WAF IP Sets
###########################

resource "aws_wafv2_ip_set" "allowed_ips_ipv4" {
  count              = var.enable_waf ? 1 : 0
  name               = "${var.stack_name}-allowed-ips-ipv4"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.waf_allowed_cidrs_ipv4

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-allowed-ips-ipv4"
      Environment = var.environment
    }
  )
}

resource "aws_wafv2_ip_set" "allowed_ips_ipv6" {
  count              = var.enable_waf ? 1 : 0
  name               = "${var.stack_name}-allowed-ips-ipv6"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = local.waf_allowed_cidrs_ipv6

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-allowed-ips-ipv6"
      Environment = var.environment
    }
  )
}

###########################
# WAF Web ACL
###########################

resource "aws_wafv2_web_acl" "this" {
  count       = var.enable_waf ? 1 : 0
  name        = "${var.stack_name}-waf"
  scope       = "REGIONAL"
  description = "WAF for RunsOn App Runner - restricts access to GitHub webhook IP ranges"

  default_action {
    block {}
  }

  # Rule for IPv4 addresses
  dynamic "rule" {
    for_each = var.enable_waf ? [1] : []
    content {
      name     = "AllowedIPsIPv4"
      priority = 1

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowed_ips_ipv4[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.stack_name}-allowed-ips-ipv4"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule for IPv6 addresses
  dynamic "rule" {
    for_each = var.enable_waf ? [1] : []
    content {
      name     = "AllowedIPsIPv6"
      priority = 2

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowed_ips_ipv6[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.stack_name}-allowed-ips-ipv6"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.stack_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-waf"
      Environment = var.environment
    }
  )
}

###########################
# WAF Web ACL Association with App Runner
###########################

resource "aws_wafv2_web_acl_association" "apprunner" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = aws_apprunner_service.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}

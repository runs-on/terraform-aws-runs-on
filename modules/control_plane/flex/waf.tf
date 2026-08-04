# modules/flex_control_plane/waf.tf
# AWS WAF configuration for public ingress

resource "aws_wafv2_ip_set" "allowed_ips_ipv4" {
  count              = local.using_managed_public_ingress_waf ? 1 : 0
  name               = "${var.stack_name}-allowed-ips-ipv4"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  # The sync seed invocation populates these before WAF association; the hourly Lambda owns updates after that.
  addresses = []

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-allowed-ips-ipv4"
    }
  )

  lifecycle {
    ignore_changes = [addresses]
  }
}

resource "aws_wafv2_ip_set" "allowed_ips_ipv6" {
  count              = local.using_managed_public_ingress_waf ? 1 : 0
  name               = "${var.stack_name}-allowed-ips-ipv6"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  # The sync seed invocation populates these before WAF association; the hourly Lambda owns updates after that.
  addresses = []

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-allowed-ips-ipv6"
    }
  )

  lifecycle {
    ignore_changes = [addresses]
  }
}

resource "aws_cloudwatch_log_group" "github_waf_sync_lambda" {
  count             = local.using_managed_public_ingress_waf ? 1 : 0
  name              = "/runs-on/${var.stack_name}/lambda/github-waf-sync"
  retention_in_days = 14

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-waf-sync-lambda"
    }
  )
}

resource "aws_iam_role" "github_waf_sync" {
  count = local.using_managed_public_ingress_waf ? 1 : 0
  name  = "${var.stack_name}-github-waf-sync-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-waf-sync-role"
    }
  )
}

resource "aws_iam_role_policy" "github_waf_sync_logs" {
  count = local.using_managed_public_ingress_waf ? 1 : 0
  name  = "RunsOnGitHubWafSyncLogPermissions"
  role  = aws_iam_role.github_waf_sync[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.github_waf_sync_lambda[0].arn}:*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "github_waf_sync" {
  count = local.using_managed_public_ingress_waf ? 1 : 0
  name  = "RunsOnGitHubWafSyncPermissions"
  role  = aws_iam_role.github_waf_sync[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "wafv2:GetIPSet",
          "wafv2:UpdateIPSet",
        ]
        Resource = [
          aws_wafv2_ip_set.allowed_ips_ipv4[0].arn,
          aws_wafv2_ip_set.allowed_ips_ipv6[0].arn,
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "github_waf_sync" {
  count         = local.using_managed_public_ingress_waf ? 1 : 0
  function_name = "${var.stack_name}-github-waf-sync"
  role          = aws_iam_role.github_waf_sync[0].arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  timeout       = 30
  memory_size   = 256

  filename         = "${local.lambda_artifact_dir}/github-waf-sync.zip"
  source_code_hash = filebase64sha256("${local.lambda_artifact_dir}/github-waf-sync.zip")

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.github_waf_sync_lambda[0].name
  }

  environment {
    variables = {
      RUNS_ON_GITHUB_META_URL      = "https://api.github.com/meta"
      RUNS_ON_WAF_SCOPE            = "REGIONAL"
      RUNS_ON_WAF_IPV4_IP_SET_ID   = aws_wafv2_ip_set.allowed_ips_ipv4[0].id
      RUNS_ON_WAF_IPV4_IP_SET_NAME = aws_wafv2_ip_set.allowed_ips_ipv4[0].name
      RUNS_ON_WAF_IPV6_IP_SET_ID   = aws_wafv2_ip_set.allowed_ips_ipv6[0].id
      RUNS_ON_WAF_IPV6_IP_SET_NAME = aws_wafv2_ip_set.allowed_ips_ipv6[0].name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-waf-sync"
    }
  )

  depends_on = [
    aws_iam_role_policy.github_waf_sync_logs[0],
  ]
}

resource "aws_cloudwatch_event_rule" "github_waf_sync" {
  count               = local.using_managed_public_ingress_waf ? 1 : 0
  name                = "${var.stack_name}-github-waf-sync"
  description         = "Refreshes the managed public ingress WAF webhook IP allowlist every hour"
  schedule_expression = "rate(1 hour)"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-waf-sync"
    }
  )
}

resource "aws_cloudwatch_event_target" "github_waf_sync" {
  count     = local.using_managed_public_ingress_waf ? 1 : 0
  rule      = aws_cloudwatch_event_rule.github_waf_sync[0].name
  target_id = "github-waf-sync"
  arn       = aws_lambda_function.github_waf_sync[0].arn
}

resource "aws_lambda_permission" "github_waf_sync_events" {
  count         = local.using_managed_public_ingress_waf ? 1 : 0
  statement_id  = "AllowEventBridgeInvokeGitHubWafSync"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_waf_sync[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.github_waf_sync[0].arn
}

resource "aws_lambda_invocation" "github_waf_sync_seed" {
  count         = local.using_managed_public_ingress_waf ? 1 : 0
  function_name = aws_lambda_function.github_waf_sync[0].function_name
  input = jsonencode({
    input = {
      meta_url         = "https://api.github.com/meta"
      scope            = "REGIONAL"
      ipv4_ip_set_id   = aws_wafv2_ip_set.allowed_ips_ipv4[0].id
      ipv4_ip_set_name = aws_wafv2_ip_set.allowed_ips_ipv4[0].name
      ipv6_ip_set_id   = aws_wafv2_ip_set.allowed_ips_ipv6[0].id
      ipv6_ip_set_name = aws_wafv2_ip_set.allowed_ips_ipv6[0].name
    }
  })
  lifecycle_scope = "CRUD"
  triggers = {
    lambda_version = aws_lambda_function.github_waf_sync[0].source_code_hash
    ipv4_ip_set_id = aws_wafv2_ip_set.allowed_ips_ipv4[0].id
    ipv6_ip_set_id = aws_wafv2_ip_set.allowed_ips_ipv6[0].id
  }
}

resource "aws_wafv2_web_acl" "this" {
  count       = local.using_managed_public_ingress_waf ? 1 : 0
  name        = "${var.stack_name}-waf"
  scope       = "REGIONAL"
  description = "WAF for RunsOn public ingress - restricts the webhook endpoint to GitHub webhook IP ranges"

  default_action {
    block {}
  }

  rule {
    name     = "AllowNonWebhookPaths"
    priority = 1

    action {
      allow {}
    }

    statement {
      not_statement {
        statement {
          byte_match_statement {
            positional_constraint = "ENDS_WITH"
            search_string         = "/github/webhooks"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.stack_name}-allow-non-webhook-paths"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AllowWebhookIPv4"
    priority = 2

    action {
      allow {}
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            positional_constraint = "ENDS_WITH"
            search_string         = "/github/webhooks"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.allowed_ips_ipv4[0].arn
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.stack_name}-allow-webhook-ipv4"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AllowWebhookIPv6"
    priority = 3

    action {
      allow {}
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            positional_constraint = "ENDS_WITH"
            search_string         = "/github/webhooks"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.allowed_ips_ipv6[0].arn
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.stack_name}-allow-webhook-ipv6"
      sampled_requests_enabled   = true
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
      Name = "${var.stack_name}-waf"
    }
  )
}

resource "aws_wafv2_web_acl_association" "public_ingress" {
  count        = local.public_ingress_web_acl_association_enabled ? 1 : 0
  resource_arn = "arn:${local.partition}:apigateway:${var.region}::/restapis/${aws_api_gateway_rest_api.public_ingress.id}/stages/${aws_api_gateway_stage.public_ingress.stage_name}"
  web_acl_arn  = local.effective_public_ingress_web_acl_arn

  depends_on = [
    aws_lambda_invocation.github_waf_sync_seed,
  ]
}

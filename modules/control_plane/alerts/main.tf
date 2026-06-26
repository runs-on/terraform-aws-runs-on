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
  slack_webhook_enabled = trimspace(var.slack_webhook_url) != ""
  lambda_artifact_dir   = "${path.module}/../../../lambdas/dist"
}

resource "aws_sns_topic" "alerts" {
  name         = "${var.stack_name}-alerts"
  display_name = "RunsOn Alerts"

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-alerts"
    }
  )
}

resource "aws_sns_topic_policy" "alerts" {
  count = var.allow_budgets_publish ? 1 : 0

  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBudgetsPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email
}

resource "aws_iam_role" "slack_webhook" {
  count = local.slack_webhook_enabled ? 1 : 0

  name = "${var.stack_name}-slack-webhook-role"

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
    var.tags,
    {
      Name = "${var.stack_name}-slack-webhook-role"
    }
  )
}

resource "aws_cloudwatch_log_group" "slack_webhook" {
  count = local.slack_webhook_enabled ? 1 : 0

  name              = "/runs-on/${var.stack_name}/lambda/slack-webhook"
  retention_in_days = 14

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-slack-webhook"
    }
  )
}

resource "aws_iam_role_policy" "slack_webhook_logs" {
  count = local.slack_webhook_enabled ? 1 : 0

  name = "RunsOnSlackWebhookLogPermissions"
  role = aws_iam_role.slack_webhook[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.slack_webhook[0].arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "slack_webhook" {
  count = local.slack_webhook_enabled ? 1 : 0

  function_name = "${var.stack_name}-slack-webhook"
  role          = aws_iam_role.slack_webhook[0].arn
  runtime       = "python3.14"
  handler       = "index.handler"
  timeout       = 10
  memory_size   = 128

  filename         = "${local.lambda_artifact_dir}/slack-webhook.zip"
  source_code_hash = filebase64sha256("${local.lambda_artifact_dir}/slack-webhook.zip")

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.slack_webhook[0].name
  }

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      STACK_NAME        = var.stack_name
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-slack-webhook"
    }
  )

  depends_on = [
    aws_iam_role_policy.slack_webhook_logs,
  ]
}

resource "aws_lambda_permission" "slack_webhook" {
  count = local.slack_webhook_enabled ? 1 : 0

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_webhook[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "slack_webhook" {
  count = local.slack_webhook_enabled ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_webhook[0].arn

  depends_on = [aws_lambda_permission.slack_webhook]
}

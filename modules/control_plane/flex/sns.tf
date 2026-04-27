# modules/flex_control_plane/sns.tf
# SNS topics for RunsOn core module

###########################
# Alert Topic
###########################

resource "aws_sns_topic" "alerts" {
  name         = "${var.stack_name}-alerts"
  display_name = "RunsOn Alerts"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-alerts"
    }
  )
}

resource "aws_sns_topic_policy" "alerts" {
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

###########################
# Topic Subscriptions
###########################

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = local.alerts.email
}

###########################
# Slack Webhook Lambda (Optional)
###########################

# IAM Role for Slack Webhook Lambda
resource "aws_iam_role" "slack_webhook" {
  count = local.alerts.slack_webhook_url != "" ? 1 : 0

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
    local.common_tags,
    {
      Name = "${var.stack_name}-slack-webhook-role"
    }
  )
}

# Attach Lambda basic execution policy to the Slack webhook role
resource "aws_iam_role_policy_attachment" "slack_webhook_basic_execution" {
  count = local.alerts.slack_webhook_url != "" ? 1 : 0

  role       = aws_iam_role.slack_webhook[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function for Slack Webhook
resource "aws_lambda_function" "slack_webhook" {
  count = local.alerts.slack_webhook_url != "" ? 1 : 0

  function_name = "${var.stack_name}-slack-webhook"
  role          = aws_iam_role.slack_webhook[0].arn
  runtime       = "python3.11"
  handler       = "index.handler"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.slack_webhook[0].output_path
  source_code_hash = data.archive_file.slack_webhook[0].output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = local.alerts.slack_webhook_url
      STACK_NAME        = var.stack_name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-slack-webhook"
    }
  )
}

# Lambda code archive
data "archive_file" "slack_webhook" {
  count = local.alerts.slack_webhook_url != "" ? 1 : 0

  type        = "zip"
  output_path = "${local.lambda_artifact_prefix}-slack-webhook.zip"

  source {
    content  = file("${path.module}/../../../lambdas/slack_webhook.py")
    filename = "index.py"
  }
}

# Lambda permission for SNS to invoke
resource "aws_lambda_permission" "slack_webhook" {
  count = local.alerts.slack_webhook_url != "" ? 1 : 0

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_webhook[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

# SNS Subscription for Slack Webhook Lambda
resource "aws_sns_topic_subscription" "slack_webhook" {
  count = local.alerts.slack_webhook_url != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_webhook[0].arn

  depends_on = [aws_lambda_permission.slack_webhook]
}

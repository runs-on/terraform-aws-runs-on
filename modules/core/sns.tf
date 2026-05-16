# modules/core/sns.tf
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

###########################
# Topic Subscriptions (Optional)
###########################

resource "aws_sns_topic_subscription" "email" {
  count = var.email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email
}

resource "aws_sns_topic_subscription" "https" {
  count = var.alert_https_endpoint != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.alert_https_endpoint
}

###########################
# Slack Webhook Lambda (Optional)
###########################

# IAM Role for Slack Webhook Lambda
resource "aws_iam_role" "slack_webhook" {
  count = var.alert_slack_webhook_url != "" ? 1 : 0

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
  count = var.alert_slack_webhook_url != "" ? 1 : 0

  role       = aws_iam_role.slack_webhook[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function for Slack Webhook
resource "aws_lambda_function" "slack_webhook" {
  count = var.alert_slack_webhook_url != "" ? 1 : 0

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
      SLACK_WEBHOOK_URL = var.alert_slack_webhook_url
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
  count = var.alert_slack_webhook_url != "" ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/files/slack_webhook.zip"

  source {
    content  = <<-EOF
import json
import logging
import os
import time
import urllib.error
import urllib.request

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_alert_color(subject, state=None):
    """Determine the color for a Slack alert based on content."""
    if state:
        state_lower = state.lower()
        if state_lower == "alarm":
            return "danger"
        elif state_lower == "ok":
            return "good"
        elif state_lower == "insufficient_data":
            return "warning"

    if subject:
        subject_lower = subject.lower()
        if any(word in subject_lower for word in ["error", "fail", "❌"]):
            return "danger"
        elif any(word in subject_lower for word in ["warn", "⚠️", "unable"]):
            return "warning"
        elif any(word in subject_lower for word in ["success", "✅", "complete"]):
            return "good"

    return "#439FE0"  # Default blue color

def create_attachment(title, text, color, stack_name):
    """Create a Slack attachment."""
    return {
        "color": color,
        "title": title,
        "text": text,
        "footer": stack_name,
        "ts": int(time.time())
    }

def handler(event, context):
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    stack_name = os.environ.get("STACK_NAME", "RunsOn")

    if not webhook_url:
        logger.error("Slack webhook URL is not configured")
        return {"statusCode": 500, "body": "Slack webhook URL is not configured"}

    records = event.get("Records", [])
    for record in records:
        sns = record.get("Sns", {})
        subject = sns.get("Subject", "")
        message = sns.get("Message", "")

        # Base payload with username and icon
        payload = {
            "username": stack_name,
            "icon_url": "https://runs-on.com/logo.png"
        }

        # Try to parse message as JSON (CloudWatch alarms)
        try:
            alarm_data = json.loads(message)
            if "AlarmName" in alarm_data:
                # CloudWatch alarm formatting
                state = alarm_data.get("NewStateValue", "UNKNOWN")
                state_emoji = {"ALARM": ":rotating_light:", "OK": ":white_check_mark:", "INSUFFICIENT_DATA": ":warning:"}.get(state, ":question:")
                title = f"{state_emoji} CloudWatch Alarm: {state}"
                text = f"*Alarm:* {alarm_data.get('AlarmName', 'N/A')}\n*Reason:* {alarm_data.get('NewStateReason', 'N/A')}"
                color = get_alert_color(None, state)
            else:
                # JSON but not an alarm, format as code block
                title = subject if subject else "JSON Message"
                text = f"```\n{json.dumps(alarm_data, indent=2)}\n```"
                color = get_alert_color(subject)
        except (json.JSONDecodeError, TypeError):
            # Plain text message
            title = subject if subject else "Alert"
            text = message
            color = get_alert_color(subject)

        payload["attachments"] = [create_attachment(title, text, color, stack_name)]

        data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            webhook_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                logger.info("Sent alert to Slack with status %s", response.status)
        except urllib.error.HTTPError as error:
            logger.error(
                "Failed to send alert to Slack: HTTP %s %s", error.code, error.reason
            )
        except Exception as error:  # noqa: BLE001
            logger.exception("Unexpected error sending alert to Slack: %s", error)

    return {"statusCode": 200, "body": "Processed SNS records"}
EOF
    filename = "index.py"
  }
}

# Lambda permission for SNS to invoke
resource "aws_lambda_permission" "slack_webhook" {
  count = var.alert_slack_webhook_url != "" ? 1 : 0

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_webhook[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

# SNS Subscription for Slack Webhook Lambda
resource "aws_sns_topic_subscription" "slack_webhook" {
  count = var.alert_slack_webhook_url != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_webhook[0].arn

  depends_on = [aws_lambda_permission.slack_webhook]
}

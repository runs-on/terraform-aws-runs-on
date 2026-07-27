mock_provider "aws" {
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-plan-role"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:mock"
    }
  }
}

variables {
  stack_name = "test-plan"
  account_id = "123456789012"
  email      = "alerts@example.com"
  tags       = {}
}

run "email_only_alerts" {
  command = plan

  assert {
    condition     = aws_sns_topic.alerts.name == "test-plan-alerts"
    error_message = "Alert topic should be named from the stack."
  }

  assert {
    condition     = aws_sns_topic_subscription.email.endpoint == "alerts@example.com"
    error_message = "Email subscription should use the configured alert address."
  }

  assert {
    condition     = length(aws_lambda_function.slack_webhook) == 0
    error_message = "Slack webhook Lambda should be absent without a webhook URL."
  }

  assert {
    condition     = length(aws_sns_topic_policy.alerts) == 0
    error_message = "Budget publish policy should be absent by default."
  }
}

run "slack_and_budget_alerts" {
  command = plan

  variables {
    slack_webhook_url     = "https://hooks.slack.com/services/example"
    allow_budgets_publish = true
  }

  assert {
    condition     = length(aws_lambda_function.slack_webhook) == 1
    error_message = "Slack webhook Lambda should be created when a webhook URL is set."
  }

  assert {
    condition     = output.slack_webhook_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:mock"
    error_message = "Slack webhook Lambda ARN output should expose non-secret resource metadata."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.slack_webhook[0].name == "/runs-on/test-plan/lambda/slack-webhook" &&
      aws_cloudwatch_log_group.slack_webhook[0].retention_in_days == 14 &&
      try(aws_cloudwatch_log_group.slack_webhook[0].kms_key_id, null) == null &&
      aws_lambda_function.slack_webhook[0].logging_config[0].log_group == aws_cloudwatch_log_group.slack_webhook[0].name
    )
    error_message = "Slack webhook Lambda should write to its stack-scoped log group."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.slack_webhook_logs[0].policy).Statement :
      statement.Action == [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ] &&
      statement.Resource == "${aws_cloudwatch_log_group.slack_webhook[0].arn}:*"
    ])
    error_message = "Slack webhook Lambda logs policy should be scoped to its log group."
  }

  assert {
    condition     = length(aws_sns_topic_policy.alerts) == 1
    error_message = "Budget publish topic policy should be created when requested."
  }
}

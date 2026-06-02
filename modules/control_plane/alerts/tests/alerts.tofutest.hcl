mock_provider "aws" {
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
    condition     = length(aws_sns_topic_policy.alerts) == 1
    error_message = "Budget publish topic policy should be created when requested."
  }
}

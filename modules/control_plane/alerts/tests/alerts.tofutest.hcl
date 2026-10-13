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
    condition     = length(aws_budgets_budget.app_daily_budget) == 0 && length(aws_sns_topic_policy.alerts) == 0 && output.daily_budget_name == null
    error_message = "The daily budget and its publish policy should be absent by default."
  }

  assert {
    condition     = aws_sns_topic.alerts.kms_master_key_id == null
    error_message = "Alert topic should have no SSE key without a KMS key."
  }
}

run "slack_and_budget_alerts" {
  command = plan

  variables {
    slack_webhook_url       = "https://hooks.slack.com/services/example"
    daily_budget_usd        = 25
    cost_allocation_tag     = "team"
    log_retention_days      = 365
    permission_boundary_arn = "arn:aws:iam::123456789012:policy/RequiredBoundary"
    kms_key_arn             = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = aws_sns_topic.alerts.kms_master_key_id == var.kms_key_arn
    error_message = "Alert topic should use the configured KMS key."
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
    condition     = aws_iam_role.slack_webhook[0].permissions_boundary == var.permission_boundary_arn
    error_message = "The Slack webhook role should use the configured permissions boundary."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.slack_webhook[0].name == "/runs-on/test-plan/lambda/slack-webhook" &&
      aws_cloudwatch_log_group.slack_webhook[0].retention_in_days == 365 &&
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
    error_message = "Budget publish topic policy should be created with the daily budget."
  }

  assert {
    condition = (
      aws_budgets_budget.app_daily_budget[0].name == "test-plan-app-daily-budget" &&
      aws_budgets_budget.app_daily_budget[0].limit_amount == "25" &&
      aws_budgets_budget.app_daily_budget[0].time_unit == "DAILY" &&
      one(aws_budgets_budget.app_daily_budget[0].cost_filter).values == tolist(["user:team$test-plan"]) &&
      one(aws_budgets_budget.app_daily_budget[0].notification).subscriber_sns_topic_arns == toset([aws_sns_topic.alerts.arn])
    )
    error_message = "The daily budget should filter on the stack's cost allocation tag and notify the alert topic."
  }
}

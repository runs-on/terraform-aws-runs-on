module "alerts" {
  source = "../alerts"

  stack_name            = var.stack_name
  account_id            = var.account_id
  email                 = local.alerts.email
  slack_webhook_url     = local.alerts.slack_webhook_url
  allow_budgets_publish = local.operations.app_budget_daily_usd > 0
  tags                  = local.common_tags
}

moved {
  from = aws_sns_topic.alerts
  to   = module.alerts.aws_sns_topic.alerts
}

moved {
  from = aws_sns_topic_policy.alerts[0]
  to   = module.alerts.aws_sns_topic_policy.alerts[0]
}

moved {
  from = aws_sns_topic_subscription.email
  to   = module.alerts.aws_sns_topic_subscription.email
}

moved {
  from = aws_iam_role.slack_webhook[0]
  to   = module.alerts.aws_iam_role.slack_webhook[0]
}

moved {
  from = aws_iam_role_policy_attachment.slack_webhook_basic_execution[0]
  to   = module.alerts.aws_iam_role_policy_attachment.slack_webhook_basic_execution[0]
}

moved {
  from = aws_lambda_function.slack_webhook[0]
  to   = module.alerts.aws_lambda_function.slack_webhook[0]
}

moved {
  from = aws_lambda_permission.slack_webhook[0]
  to   = module.alerts.aws_lambda_permission.slack_webhook[0]
}

moved {
  from = aws_sns_topic_subscription.slack_webhook[0]
  to   = module.alerts.aws_sns_topic_subscription.slack_webhook[0]
}

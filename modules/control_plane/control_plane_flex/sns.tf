module "alerts" {
  source = "../alerts"

  stack_name              = var.stack_name
  account_id              = var.account_id
  email                   = local.alerts.email
  slack_webhook_url       = local.alerts.slack_webhook_url
  log_retention_days      = local.control_plane_log_retention_days
  daily_budget_usd        = local.operations.app_budget_daily_usd
  cost_allocation_tag     = var.cost_allocation_tag
  kms_key_arn             = local.messaging_kms_key_arn
  permission_boundary_arn = var.permission_boundary_arn
  tags                    = local.common_tags
}

moved {
  from = aws_sns_topic.alerts
  to   = module.alerts.aws_sns_topic.alerts
}

# v3.0.x declared the policy without count; chain it into the move below.
moved {
  from = aws_sns_topic_policy.alerts
  to   = aws_sns_topic_policy.alerts[0]
}

moved {
  from = aws_sns_topic_policy.alerts[0]
  to   = module.alerts.aws_sns_topic_policy.alerts[0]
}

moved {
  from = aws_budgets_budget.app_daily_budget
  to   = module.alerts.aws_budgets_budget.app_daily_budget
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

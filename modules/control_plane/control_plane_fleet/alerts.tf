module "alerts" {
  source = "../alerts"

  stack_name              = var.stack_name
  account_id              = var.account_id
  email                   = var.alerts.email
  slack_webhook_url       = var.alerts.slack_webhook_url
  log_retention_days      = local.lambda_log_retention_days
  kms_key_arn             = trimspace(var.messaging_kms_key_arn)
  permission_boundary_arn = var.permission_boundary_arn
  tags                    = var.tags
}

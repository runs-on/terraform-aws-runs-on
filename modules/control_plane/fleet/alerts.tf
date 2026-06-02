module "alerts" {
  source = "../alerts"

  stack_name        = var.stack_name
  account_id        = var.account_id
  email             = var.alerts.email
  slack_webhook_url = var.alerts.slack_webhook_url
  tags              = var.tags
}

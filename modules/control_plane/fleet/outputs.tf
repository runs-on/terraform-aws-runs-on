output "config" {
  description = "Fleet runtime configuration secret"
  value = {
    secret_arn               = aws_secretsmanager_secret.config.arn
    license_status_parameter = aws_ssm_parameter.license_status.name
  }
}

output "claims" {
  description = "Fleet claim ledger table"
  value = {
    table_name = aws_dynamodb_table.claims.name
    table_arn  = aws_dynamodb_table.claims.arn
  }
}

output "runtime" {
  description = "Fleet runtime ECS resources"
  value       = module.runtime.runtime
}

output "alerts" {
  description = "Fleet alerting resources"
  value = {
    topic_arn                = module.alerts.topic_arn
    topic_name               = module.alerts.topic_name
    slack_webhook_lambda_arn = module.alerts.slack_webhook_lambda_arn
  }
}

output "workflow_contract" {
  description = "Fleet workflow targeting contract"
  value = {
    label = local.workflow_target_contract
  }
}

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

output "workflow_contract" {
  description = "Fleet workflow targeting contract"
  value = {
    label = local.workflow_target_contract
  }
}

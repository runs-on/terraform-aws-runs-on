output "topic_arn" {
  description = "SNS topic ARN for RunsOn alerts."
  value       = aws_sns_topic.alerts.arn
}

output "topic_name" {
  description = "SNS topic name for RunsOn alerts."
  value       = aws_sns_topic.alerts.name
}

output "slack_webhook_lambda_arn" {
  description = "Slack webhook Lambda ARN when Slack alerting is enabled."
  value       = local.slack_webhook_enabled ? aws_lambda_function.slack_webhook[0].arn : null
}

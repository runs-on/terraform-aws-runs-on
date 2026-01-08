# modules/core/outputs.tf
# Output values from the core module

output "apprunner_service_id" {
  description = "ID of the App Runner service"
  value       = aws_apprunner_service.this.service_id
}

output "apprunner_service_arn" {
  description = "ARN of the App Runner service"
  value       = aws_apprunner_service.this.arn
}

output "apprunner_service_url" {
  description = "URL of the App Runner service"
  value       = aws_apprunner_service.this.service_url
}

output "apprunner_service_status" {
  description = "Status of the App Runner service"
  value       = aws_apprunner_service.this.status
}

output "apprunner_log_group_name" {
  description = "CloudWatch log group name for App Runner service"
  value       = "/aws/apprunner/${aws_apprunner_service.this.service_name}/${aws_apprunner_service.this.service_id}/application"
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS alerts topic"
  value       = aws_sns_topic.alerts.name
}

output "sqs_queue_main_url" {
  description = "URL of the main SQS queue"
  value       = aws_sqs_queue.main.url
}

output "sqs_queue_main_arn" {
  description = "ARN of the main SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "sqs_queue_jobs_url" {
  description = "URL of the jobs SQS queue"
  value       = aws_sqs_queue.jobs.url
}

output "sqs_queue_github_url" {
  description = "URL of the github SQS queue"
  value       = aws_sqs_queue.github.url
}

output "sqs_queue_pool_url" {
  description = "URL of the pool SQS queue"
  value       = aws_sqs_queue.pool.url
}

output "sqs_queue_housekeeping_url" {
  description = "URL of the housekeeping SQS queue"
  value       = aws_sqs_queue.housekeeping.url
}

output "sqs_queue_termination_url" {
  description = "URL of the termination SQS queue"
  value       = aws_sqs_queue.termination.url
}

output "sqs_queue_events_url" {
  description = "URL of the events SQS queue"
  value       = aws_sqs_queue.events.url
}

output "dynamodb_locks_table_name" {
  description = "Name of the DynamoDB locks table"
  value       = aws_dynamodb_table.locks.name
}

output "dynamodb_locks_table_arn" {
  description = "ARN of the DynamoDB locks table"
  value       = aws_dynamodb_table.locks.arn
}

output "dynamodb_workflow_jobs_table_name" {
  description = "Name of the DynamoDB workflow jobs table"
  value       = aws_dynamodb_table.workflow_jobs.name
}

output "dynamodb_workflow_jobs_table_arn" {
  description = "ARN of the DynamoDB workflow jobs table"
  value       = aws_dynamodb_table.workflow_jobs.arn
}

output "eventbridge_spot_interruption_rule_arn" {
  description = "ARN of the EventBridge spot interruption rule"
  value       = aws_cloudwatch_event_rule.spot_interruption.arn
}

output "app_alarm_arn" {
  description = "ARN of the App Runner daily budget alarm"
  value       = aws_cloudwatch_metric_alarm.app_daily_budget.arn
}

output "sqs_alarm_main_arn" {
  description = "ARN of the SQS Main Queue oldest message alarm"
  value       = var.sqs_queue_oldest_message_threshold_seconds > 0 ? aws_cloudwatch_metric_alarm.sqs_main_oldest_message[0].arn : null
}

output "dashboard_url" {
  description = "URL to the CloudWatch Dashboard"
  value       = var.enable_dashboard ? "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.stack_name}-Dashboard" : null
}

output "dashboard_name" {
  description = "Name of the CloudWatch Dashboard"
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.runs_on[0].dashboard_name : null
}

output "slack_webhook_lambda_arn" {
  description = "ARN of the Slack webhook Lambda function"
  value       = var.alert_slack_webhook_url != "" ? aws_lambda_function.slack_webhook[0].arn : null
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].id : null
}

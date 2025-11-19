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

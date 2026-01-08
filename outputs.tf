# outputs.tf
# Root module outputs for RunsOn infrastructure

###########################
# General Information
###########################

output "stack_name" {
  description = "The stack name used for this deployment"
  value       = var.stack_name
}

output "aws_account_id" {
  description = "AWS Account ID where RunsOn is deployed"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS region where RunsOn is deployed"
  value       = local.region
}

###########################
# Storage Outputs
###########################

output "config_bucket_name" {
  description = "Name of the S3 configuration bucket"
  value       = module.storage.config_bucket_name
}

output "cache_bucket_name" {
  description = "Name of the S3 cache bucket"
  value       = module.storage.cache_bucket_name
}

output "logging_bucket_name" {
  description = "Name of the S3 logging bucket"
  value       = module.storage.logging_bucket_name
}

###########################
# Compute Outputs
###########################

output "ec2_instance_role_name" {
  description = "Name of the EC2 instance IAM role"
  value       = module.compute.ec2_instance_role_name
}

output "ec2_instance_role_arn" {
  description = "ARN of the EC2 instance IAM role"
  value       = module.compute.ec2_instance_role_arn
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = module.compute.ec2_instance_profile_arn
}

output "ec2_instance_log_group_name" {
  description = "CloudWatch log group name for EC2 instances"
  value       = module.compute.log_group_name
}

output "launch_template_linux_default_id" {
  description = "ID of the Linux default launch template"
  value       = module.compute.launch_template_linux_default_id
}

output "launch_template_windows_default_id" {
  description = "ID of the Windows default launch template"
  value       = module.compute.launch_template_windows_default_id
}

output "launch_template_linux_private_id" {
  description = "ID of the Linux private launch template (if private networking enabled)"
  value       = module.compute.launch_template_linux_private_id
}

output "launch_template_windows_private_id" {
  description = "ID of the Windows private launch template (if private networking enabled)"
  value       = module.compute.launch_template_windows_private_id
}

output "security_group_ids" {
  description = "Security group IDs being used (created or provided)"
  value       = local.effective_security_group_ids
}

###########################
# Core Service Outputs
###########################

output "apprunner_service_url" {
  description = "URL of the RunsOn App Runner service"
  value       = module.core.apprunner_service_url
  sensitive   = false
}

output "apprunner_service_arn" {
  description = "ARN of the RunsOn App Runner service"
  value       = module.core.apprunner_service_arn
}

output "apprunner_service_status" {
  description = "Status of the RunsOn App Runner service"
  value       = module.core.apprunner_service_status
}

output "apprunner_log_group_name" {
  description = "CloudWatch log group name for App Runner service"
  value       = module.core.apprunner_log_group_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = module.core.sns_topic_arn
}

###########################
# SQS Queue Outputs
###########################

output "sqs_queue_main_url" {
  description = "URL of the main SQS queue"
  value       = module.core.sqs_queue_main_url
}

output "sqs_queue_jobs_url" {
  description = "URL of the jobs SQS queue"
  value       = module.core.sqs_queue_jobs_url
}

output "sqs_queue_github_url" {
  description = "URL of the GitHub SQS queue"
  value       = module.core.sqs_queue_github_url
}

output "sqs_queue_pool_url" {
  description = "URL of the pool SQS queue"
  value       = module.core.sqs_queue_pool_url
}

output "sqs_queue_housekeeping_url" {
  description = "URL of the housekeeping SQS queue"
  value       = module.core.sqs_queue_housekeeping_url
}

output "sqs_queue_termination_url" {
  description = "URL of the termination SQS queue"
  value       = module.core.sqs_queue_termination_url
}

output "sqs_queue_events_url" {
  description = "URL of the events SQS queue"
  value       = module.core.sqs_queue_events_url
}

###########################
# DynamoDB Outputs
###########################

output "dynamodb_locks_table_name" {
  description = "Name of the DynamoDB locks table"
  value       = module.core.dynamodb_locks_table_name
}

output "dynamodb_workflow_jobs_table_name" {
  description = "Name of the DynamoDB workflow jobs table"
  value       = module.core.dynamodb_workflow_jobs_table_name
}

###########################
# Optional Features Outputs
###########################

output "efs_file_system_id" {
  description = "ID of the EFS file system (if enabled)"
  value       = var.enable_efs ? module.optional.efs_file_system_id : null
}

output "efs_file_system_dns_name" {
  description = "DNS name of the EFS file system (if enabled)"
  value       = var.enable_efs ? module.optional.efs_file_system_dns_name : null
}

output "ecr_repository_url" {
  description = "URL of the ECR repository (if enabled)"
  value       = var.enable_ecr ? module.optional.ecr_repository_url : null
}

output "ecr_repository_name" {
  description = "Name of the ECR repository (if enabled)"
  value       = var.enable_ecr ? module.optional.ecr_repository_name : null
}

###########################
# Monitoring Outputs
###########################

output "dashboard_url" {
  description = "URL to the CloudWatch Dashboard (if enabled)"
  value       = module.core.dashboard_url
}

output "dashboard_name" {
  description = "Name of the CloudWatch Dashboard (if enabled)"
  value       = module.core.dashboard_name
}

###########################
# WAF Outputs
###########################

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL (if enabled)"
  value       = var.enable_waf ? module.core.waf_web_acl_arn : null
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL (if enabled)"
  value       = var.enable_waf ? module.core.waf_web_acl_id : null
}

###########################
# Usage Information
###########################

output "getting_started" {
  description = "Quick start guide for using this RunsOn deployment"
  value = <<-EOT
    RunsOn Infrastructure Deployed Successfully!

    Stack Name: ${var.stack_name}
    Region: ${local.region}
    Environment: ${var.environment}
${var.environment != "production" ? <<-WARNING

    ⚠️  WARNING: Non-production environment detected!
    Your GitHub workflows must include 'env:${var.environment}' in the runs-on label.
    Example: runs-on: runs-on=$family/env:${var.environment}
    See: https://runs-on.com/configuration/job-labels/#env
WARNING
: ""}
    Get Started by clicking here -> https://${module.core.apprunner_service_url}

    Read more on https://runs-on.com/docs or visit https://runs-on.com/guides/troubleshoot/ to fix common issues.
  EOT
}



# modules/core/variables.tf
# Input variables for the core module

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "app_alarm_daily_minutes" {
  description = "Daily budget in minutes for the App Runner service"
  type        = number
}

variable "sqs_queue_oldest_message_threshold_seconds" {
  description = "Threshold in seconds for oldest message in SQS queues"
  type        = number
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
}

variable "cost_allocation_tag" {
  description = "Tag key for cost allocation"
  type        = string
}

variable "github_organization" {
  description = "GitHub organization or username"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

variable "github_enterprise_url" {
  description = "GitHub Enterprise URL (optional)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where RunsOn is deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for App Runner"
  type        = list(string)
}

variable "config_bucket_name" {
  description = "S3 bucket name for configuration"
  type        = string
}

variable "config_bucket_arn" {
  description = "S3 bucket ARN for configuration"
  type        = string
}

variable "cache_bucket_name" {
  description = "S3 bucket name for cache"
  type        = string
}

variable "cache_bucket_arn" {
  description = "S3 bucket ARN for cache"
  type        = string
}

variable "ec2_instance_role_name" {
  description = "Name of the EC2 instance IAM role"
  type        = string
}

variable "ec2_instance_role_arn" {
  description = "ARN of the EC2 instance IAM role"
  type        = string
}

variable "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  type        = string
}

variable "launch_template_linux_default_id" {
  description = "ID of the Linux default launch template"
  type        = string
}

variable "launch_template_windows_default_id" {
  description = "ID of the Windows default launch template"
  type        = string
}

variable "launch_template_linux_private_id" {
  description = "ID of the Linux private launch template"
  type        = string
}

variable "launch_template_windows_private_id" {
  description = "ID of the Windows private launch template"
  type        = string
}

variable "app_image" {
  description = "App Runner image identifier"
  type        = string
}

variable "app_tag" {
  description = "Application version tag"
  type        = string
}

variable "bootstrap_tag" {
  description = "Bootstrap script version tag"
  type        = string
}

variable "app_cpu" {
  description = "CPU units for App Runner service"
  type        = number
}

variable "app_memory" {
  description = "Memory in MB for App Runner service"
  type        = number
}

variable "private_mode" {
  description = "Private networking mode: 'false', 'true', 'always', or 'only'"
  type        = string
}

variable "app_debug" {
  description = "Enable debug mode for RunsOn stack"
  type        = bool
}

variable "ssh_allowed" {
  description = "Allow SSH access to runners"
  type        = bool
}

variable "ec2_queue_size" {
  description = "EC2 queue size"
  type        = number
}

variable "ebs_encryption_key_id" {
  description = "KMS key ID for EBS encryption (leave empty for AWS managed key)"
  type        = string
}

variable "github_api_strategy" {
  description = "Strategy for GitHub API calls (normal, conservative)"
  type        = string
}

variable "default_admins" {
  description = "Comma-separated list of default admin usernames"
  type        = string
}

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes for runners"
  type        = number
}

variable "runner_config_auto_extends_from" {
  description = "Repository to auto-extend runner config from (e.g., '.github-private')"
  type        = string
}

variable "runner_default_disk_size" {
  description = "Default EBS volume size in GB"
  type        = number
}

variable "runner_default_volume_throughput" {
  description = "Default EBS volume throughput in MiB/s"
  type        = number
}

variable "runner_large_disk_size" {
  description = "Large EBS volume size in GB"
  type        = number
}

variable "runner_large_volume_throughput" {
  description = "Large EBS volume throughput in MiB/s"
  type        = number
}

variable "runner_custom_tags" {
  description = "Custom tags for runners"
  type        = list(string)
}

variable "enable_cost_reports" {
  description = "Enable automated cost reports"
  type        = bool
}

variable "server_password" {
  description = "Password for RunsOn server admin interface"
  type        = string
  sensitive   = true
}

variable "spot_circuit_breaker" {
  description = "Spot circuit breaker config (e.g., '2/15/30' = 2 failures in 15min, block for 30min)"
  type        = string
}

variable "integration_step_security_api_key" {
  description = "StepSecurity integration API key"
  type        = string
  sensitive   = true
}

variable "otel_exporter_endpoint" {
  description = "OpenTelemetry exporter endpoint"
  type        = string
}

variable "otel_exporter_headers" {
  description = "OpenTelemetry exporter headers"
  type        = string
  sensitive   = true
}

variable "logger_level" {
  description = "Log level: debug, info, warn, or error"
  type        = string
}

variable "email" {
  description = "Email address for alerts"
  type        = string
}

variable "alert_https_endpoint" {
  description = "HTTPS endpoint for alerts"
  type        = string
}

variable "alert_slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
}

variable "enable_dashboard" {
  description = "Create a CloudWatch dashboard for monitoring RunsOn operations"
  type        = bool
}

variable "enable_waf" {
  description = "Enable AWS WAF for App Runner service"
  type        = bool
  default     = false
}

variable "waf_allowed_ipv4_cidrs" {
  description = "List of IPv4 CIDR blocks to allow through WAF (in addition to GitHub webhook IPs)"
  type        = list(string)
  default     = []
}

variable "waf_allowed_ipv6_cidrs" {
  description = "List of IPv6 CIDR blocks to allow through WAF (in addition to GitHub webhook IPs)"
  type        = list(string)
  default     = []
}

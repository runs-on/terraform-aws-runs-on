# modules/core/variables.tf
# Input variables for the core module

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
  default     = "production"
}

variable "cost_allocation_tag" {
  description = "Tag key for cost allocation"
  type        = string
  default     = "CostCenter"
}

variable "github_organization" {
  description = "GitHub organization or username"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key"
  type        = string
  sensitive   = true
}

variable "github_enterprise_url" {
  description = "GitHub Enterprise URL (optional)"
  type        = string
  default     = ""
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
  default     = []
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
  default     = null
}

variable "launch_template_windows_private_id" {
  description = "ID of the Windows private launch template"
  type        = string
  default     = null
}

variable "app_image" {
  description = "App Runner image identifier"
  type        = string
  default     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:v2.10.0"
}

variable "app_tag" {
  description = "Application version tag"
  type        = string
  default     = "v2.10.0"
}

variable "bootstrap_tag" {
  description = "Bootstrap script version tag"
  type        = string
  default     = "v0.1.12"
}

variable "app_cpu" {
  description = "CPU units for App Runner service"
  type        = number
  default     = 256
}

variable "app_memory" {
  description = "Memory in MB for App Runner service"
  type        = number
  default     = 512
}

variable "private_mode" {
  description = "Private networking mode: 'false', 'true', 'always', or 'only'"
  type        = string
  default     = "false"
}

variable "app_debug" {
  description = "Enable debug mode for RunsOn stack"
  type        = bool
  default     = false
}

variable "ssh_allowed" {
  description = "Allow SSH access to runners"
  type        = bool
  default     = true
}

variable "ec2_queue_size" {
  description = "EC2 queue size"
  type        = number
  default     = 2
}

variable "ebs_encryption_key_id" {
  description = "KMS key ID for EBS encryption"
  type        = string
  default     = ""
}

variable "github_api_strategy" {
  description = "GitHub API strategy"
  type        = string
  default     = "normal"
}

variable "default_admins" {
  description = "Default admins"
  type        = string
  default     = ""
}

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes for runners"
  type        = number
  default     = 720
}

variable "runner_config_auto_extends_from" {
  description = "Runner config auto extends from"
  type        = string
  default     = ".github-private"
}

variable "runner_default_disk_size" {
  description = "Default EBS volume size in GB"
  type        = number
  default     = 40
}

variable "runner_default_volume_throughput" {
  description = "Default EBS volume throughput in MiB/s"
  type        = number
  default     = 400
}

variable "runner_large_disk_size" {
  description = "Large EBS volume size in GB"
  type        = number
  default     = 80
}

variable "runner_large_volume_throughput" {
  description = "Large EBS volume throughput in MiB/s"
  type        = number
  default     = 750
}

variable "runner_custom_tags" {
  description = "Custom tags for runners"
  type        = list(string)
  default     = []
}

variable "enable_cost_reports" {
  description = "Enable automated cost reports"
  type        = bool
  default     = true
}

variable "server_password" {
  description = "Server password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "spot_circuit_breaker" {
  description = "Spot circuit breaker configuration"
  type        = string
  default     = ""
}

variable "integration_step_security_api_key" {
  description = "StepSecurity integration API key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "otel_exporter_endpoint" {
  description = "OpenTelemetry exporter endpoint"
  type        = string
  default     = ""
}

variable "otel_exporter_headers" {
  description = "OpenTelemetry exporter headers"
  type        = string
  default     = ""
  sensitive   = true
}

variable "logger_level" {
  description = "Logger level"
  type        = string
  default     = "info"
}

variable "email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "alert_https_endpoint" {
  description = "HTTPS endpoint for alerts"
  type        = string
  default     = ""
}

variable "alert_slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# variables.tf
# Root module variables for RunsOn infrastructure
# Organized by submodule usage for clarity

###########################
# Shared Configuration
# Variables used across multiple modules
###########################

variable "stack_name" {
  description = "Name for the RunsOn stack (used for resource naming)"
  type        = string
  default     = "runs-on"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.stack_name))
    error_message = "Stack name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name used for resource tagging and RunsOn job filtering. RunsOn will only process jobs with an 'env' label matching this value. See https://runs-on.com/configuration/environments/ for details."
  type        = string
  default     = "production"
}

variable "cost_allocation_tag" {
  description = "Name of the tag key used for cost allocation and tracking"
  type        = string
  default     = "stack"
}

variable "tags" {
  description = "Tags to apply to all resources. Note: 'runs-on-stack-name' is added automatically for resource discovery."
  type        = map(string)
  default     = {}
}

###########################
# GitHub Configuration
# Used by: core module
###########################

variable "github_organization" {
  description = "GitHub organization or username for RunsOn integration"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.github_organization))
    error_message = "GitHub organization must contain only alphanumeric characters and hyphens."
  }
}

variable "github_enterprise_url" {
  description = "GitHub Enterprise Server URL (optional, leave empty for github.com)"
  type        = string
  default     = ""
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

###########################
# Networking Configuration
# Used by: core, compute, optional modules
###########################

variable "vpc_id" {
  description = "VPC ID where RunsOn infrastructure will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier (vpc-*)."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for runner instances (requires at least 1)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 1
    error_message = "At least one public subnet ID is required."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for runner instances (required if private_mode is not 'false')"
  type        = list(string)
  default     = []
}

variable "private_mode" {
  description = "Private networking mode: 'false' (disabled), 'true' (opt-in with label), 'always' (default with opt-out), 'only' (forced, no public option)"
  type        = string
  default     = "false"

  validation {
    condition     = contains(["false", "true", "always", "only"], var.private_mode)
    error_message = "Private mode must be one of: false, true, always, only."
  }

  validation {
    condition     = var.private_mode == "false" || length(var.private_subnet_ids) > 0
    error_message = "At least one private subnet ID is required for private networking."
  }
}

variable "security_group_ids" {
  description = "Security group IDs for runner instances and App Runner service. If empty list provided, security groups will be created automatically."
  type        = list(string)
  default     = []
}

variable "ssh_allowed" {
  description = "Allow SSH access to runner instances"
  type        = bool
  default     = true
}

variable "ssh_cidr_range" {
  description = "CIDR range allowed for SSH access to runner instances (only applies if ssh_allowed is true)"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_cidr_range, 0))
    error_message = "ssh_cidr_range must be a valid IPv4 CIDR block."
  }
}

###########################
# Storage Configuration
# Used by: storage module
###########################

variable "cache_expiration_days" {
  description = "Number of days to retain cache artifacts in S3 before expiration"
  type        = number
  default     = 10

  validation {
    condition     = var.cache_expiration_days >= 1 && var.cache_expiration_days <= 365
    error_message = "Cache expiration days must be between 1 and 365."
  }
}

variable "force_destroy_buckets" {
  description = "Allow S3 buckets to be destroyed even when not empty. Set to false for production environments to prevent accidental data loss."
  type        = bool
  default     = false
}

###########################
# Compute Configuration
# Used by: compute module
###########################

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs for EC2 instances"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "permission_boundary_arn" {
  description = "IAM permissions boundary ARN to attach to all IAM roles (optional)"
  type        = string
  default     = ""
}

variable "detailed_monitoring_enabled" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances (increases costs)"
  type        = bool
  default     = false
}

variable "ipv6_enabled" {
  description = "Enable IPv6 support for runner instances"
  type        = bool
  default     = false
}

variable "ebs_encryption_enabled" {
  description = "Enable encryption for EBS volumes on runner instances"
  type        = bool
  default     = false
}

variable "ebs_encryption_key_id" {
  description = "KMS key ID for EBS volume encryption (leave empty for AWS managed key)"
  type        = string
  default     = ""
}

variable "runner_default_disk_size" {
  description = "Default EBS volume size in GB for runner instances"
  type        = number
  default     = 40

  validation {
    condition     = var.runner_default_disk_size >= 8 && var.runner_default_disk_size <= 16384
    error_message = "Disk size must be between 8 GB and 16384 GB."
  }
}

variable "runner_default_volume_throughput" {
  description = "Default EBS volume throughput in MiB/s (gp3 volumes only)"
  type        = number
  default     = 400

  validation {
    condition     = var.runner_default_volume_throughput >= 125 && var.runner_default_volume_throughput <= 2000
    error_message = "Volume throughput must be between 125 and 2000 MiB/s for gp3 volumes."
  }
}

variable "runner_large_disk_size" {
  description = "Large EBS volume size in GB for runner instances requiring more storage"
  type        = number
  default     = 80

  validation {
    condition     = var.runner_large_disk_size >= 20 && var.runner_large_disk_size <= 16384
    error_message = "Large disk size must be between 20 GB and 16384 GB."
  }
}

variable "runner_large_volume_throughput" {
  description = "Large EBS volume throughput in MiB/s (gp3 volumes only)"
  type        = number
  default     = 750

  validation {
    condition     = var.runner_large_volume_throughput >= 125 && var.runner_large_volume_throughput <= 2000
    error_message = "Large volume throughput must be between 125 and 2000 MiB/s for gp3 volumes."
  }
}

###########################
# App Runner Configuration
# Used by: core module
###########################

variable "app_image" {
  description = "App Runner container image for RunsOn service"
  type        = string
  default     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:v2.11.0@sha256:875bcd8a36be7be78509a4c8371cdb4bff01af06c49f4a2d2a2647e3bf44bac5"
}

variable "app_tag" {
  description = "Application version tag for RunsOn service"
  type        = string
  default     = "v2.11.0"
}

variable "bootstrap_tag" {
  description = "Bootstrap script version tag"
  type        = string
  default     = "v0.1.12"
}

variable "app_cpu" {
  description = "CPU units for App Runner service (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.app_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "app_memory" {
  description = "Memory in MB for App Runner service (512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288)"
  type        = number
  default     = 512

  validation {
    condition     = contains([512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288], var.app_memory)
    error_message = "Memory must be one of: 512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288."
  }
}

variable "app_debug" {
  description = "Enable debug mode for RunsOn stack (prevents auto-shutdown of failed runner instances)"
  type        = bool
  default     = false
}

###########################
# Runner Configuration
# Used by: core module
###########################

variable "ec2_queue_size" {
  description = "Maximum number of EC2 instances in queue"
  type        = number
  default     = 2

  validation {
    condition     = var.ec2_queue_size >= 1 && var.ec2_queue_size <= 1000
    error_message = "EC2 queue size must be between 1 and 1000."
  }
}

variable "github_api_strategy" {
  description = "Strategy for GitHub API calls (normal, conservative)"
  type        = string
  default     = "normal"

  validation {
    condition     = contains(["normal", "conservative"], var.github_api_strategy)
    error_message = "GitHub API strategy must be one of: normal, conservative."
  }
}

variable "default_admins" {
  description = "Comma-separated list of default admin usernames"
  type        = string
  default     = ""
}

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes for runners before forced termination"
  type        = number
  default     = 720

  validation {
    condition     = var.runner_max_runtime >= 1
    error_message = "Runner max runtime must be at least 1 minute."
  }
}

variable "runner_config_auto_extends_from" {
  description = "Auto-extend runner configuration from this base config"
  type        = string
  default     = ".github-private"
}

variable "runner_custom_tags" {
  description = "Custom tags to apply to runner instances (comma-separated list)"
  type        = list(string)
  default     = []
}

###########################
# Operational Configuration
# Used by: core module
###########################

variable "enable_cost_reports" {
  description = "Enable automated cost reports sent to alert email"
  type        = bool
  default     = true
}

variable "server_password" {
  description = "Password for RunsOn server admin interface (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "spot_circuit_breaker" {
  description = "Spot instance circuit breaker configuration (e.g., '2/15/30' = 2 failures in 15min, block for 30min)"
  type        = string
  default     = "2/15/30"
}

###########################
# Monitoring & Alarms
# Used by: core module
###########################

variable "app_alarm_daily_minutes" {
  description = "Daily budget in minutes for the App Runner service before triggering an alarm"
  type        = number
  default     = 4000
}

variable "sqs_queue_oldest_message_threshold_seconds" {
  description = "Threshold in seconds for oldest message in SQS queues before triggering an alarm (0 to disable)"
  type        = number
  default     = 0
}

variable "enable_dashboard" {
  description = "Create a CloudWatch dashboard for monitoring RunsOn operations (number of jobs processed, rate limit status, last error messages, etc.)"
  type        = bool
  default     = true
}

###########################
# Integration Configuration
# Used by: core module
###########################

variable "integration_step_security_api_key" {
  description = "API key for StepSecurity integration (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "otel_exporter_endpoint" {
  description = "OpenTelemetry exporter endpoint for observability (optional)"
  type        = string
  default     = ""
}

variable "otel_exporter_headers" {
  description = "OpenTelemetry exporter headers (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "logger_level" {
  description = "Logging level for RunsOn service (debug, info, warn, error)"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.logger_level)
    error_message = "Logger level must be one of: debug, info, warn, error."
  }
}

###########################
# Alert Configuration
# Used by: core module
###########################

variable "email" {
  description = "Email address for alerts and notifications (requires confirmation)"
  type        = string
}

variable "alert_https_endpoint" {
  description = "HTTPS endpoint for alert notifications (optional)"
  type        = string
  default     = ""
}

variable "alert_slack_webhook_url" {
  description = "Slack webhook URL for alert notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

###########################
# Optional Features
# Used by: optional module
###########################

variable "enable_efs" {
  description = "Enable EFS file system for shared storage across runners"
  type        = bool
  default     = false
}

variable "enable_ecr" {
  description = "Enable ECR repository for ephemeral Docker image storage"
  type        = bool
  default     = false
}

variable "prevent_destroy_optional_resources" {
  description = "Prevent destruction of EFS and ECR resources. Set to true for production environments to protect against accidental data loss."
  type        = bool
  default     = true
}

variable "force_delete_ecr" {
  description = "Allow ECR repository to be deleted even when it contains images. Set to true for testing environments."
  type        = bool
  default     = false
}

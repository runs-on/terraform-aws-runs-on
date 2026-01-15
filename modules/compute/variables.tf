# modules/compute/variables.tf
# Input variables for the compute module

variable "region" {
  description = "AWS region where resources are deployed"
  type        = string
}

variable "account_id" {
  description = "AWS account ID for resource ARN construction"
  type        = string
}

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "cost_allocation_tag" {
  description = "Tag key for cost allocation"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
}

variable "config_bucket_name" {
  description = "S3 bucket name for configuration storage"
  type        = string
}

variable "config_bucket_arn" {
  description = "S3 bucket ARN for configuration storage"
  type        = string
}

variable "cache_bucket_name" {
  description = "S3 bucket name for cache storage"
  type        = string
}

variable "cache_bucket_arn" {
  description = "S3 bucket ARN for cache storage"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs for EC2 instances"
  type        = list(string)
}

variable "log_retention_days" {
  description = "Days to retain CloudWatch logs"
  type        = number
}

variable "permission_boundary_arn" {
  description = "IAM permission boundary ARN"
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

variable "detailed_monitoring_enabled" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
}

variable "ipv6_enabled" {
  description = "Enable IPv6 for runners"
  type        = bool
}

variable "ebs_encryption_enabled" {
  description = "Enable EBS volume encryption"
  type        = bool
}

variable "runner_default_disk_size" {
  description = "Default EBS volume size in GB"
  type        = number
}

variable "runner_default_volume_throughput" {
  description = "Default EBS volume throughput in MiB/s"
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

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes for runners"
  type        = number
}

variable "enable_efs" {
  description = "Whether EFS is enabled"
  type        = bool
}

variable "efs_file_system_id" {
  description = "EFS file system ID (optional)"
  type        = string
}

variable "enable_ecr" {
  description = "Whether ECR is enabled"
  type        = bool
}

variable "ephemeral_registry_arn" {
  description = "ECR repository ARN (optional)"
  type        = string
}

variable "ephemeral_registry_uri" {
  description = "ECR repository URI (optional)"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
}

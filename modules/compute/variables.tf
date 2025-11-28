# modules/compute/variables.tf
# Input variables for the compute module

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "cost_allocation_tag" {
  description = "Tag key for cost allocation"
  type        = string
  default     = "CostCenter"
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
  default     = "production"
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

variable "log_group_name" {
  description = "CloudWatch log group name for EC2 instances"
  type        = string
  default     = "/runs-on/ec2"
}

variable "log_retention_days" {
  description = "Days to retain CloudWatch logs"
  type        = number
  default     = 7
}

variable "permission_boundary_arn" {
  description = "IAM permission boundary ARN"
  type        = string
  default     = ""
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

variable "linux_ami_id" {
  description = "AMI ID for Linux runners"
  type        = string
  default     = ""
}

variable "windows_ami_id" {
  description = "AMI ID for Windows runners"
  type        = string
  default     = ""
}

variable "detailed_monitoring_enabled" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

variable "ipv6_enabled" {
  description = "Enable IPv6 for runners"
  type        = bool
  default     = false
}

variable "ebs_encryption_enabled" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = false
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

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes for runners"
  type        = number
  default     = 720
}

variable "enable_efs" {
  description = "Whether EFS is enabled"
  type        = bool
  default     = false
}

variable "efs_file_system_id" {
  description = "EFS file system ID (optional)"
  type        = string
  default     = ""
}

variable "enable_ecr" {
  description = "Whether ECR is enabled"
  type        = bool
  default     = false
}

variable "ephemeral_registry_arn" {
  description = "ECR repository ARN (optional)"
  type        = string
  default     = ""
}

variable "ephemeral_registry_uri" {
  description = "ECR repository URI (optional)"
  type        = string
  default     = ""
}

variable "custom_policy_json" {
  description = "Custom IAM policy JSON (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

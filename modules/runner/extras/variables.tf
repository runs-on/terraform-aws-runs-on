variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.stack_name))
    error_message = "Stack name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cache_expiration_days" {
  description = "Number of days to retain cache artifacts before expiration"
  type        = number

  validation {
    condition     = var.cache_expiration_days >= 1 && var.cache_expiration_days <= 365
    error_message = "Cache expiration days must be between 1 and 365."
  }
}

variable "force_destroy_buckets" {
  description = "Allow S3 buckets to be destroyed even when not empty"
  type        = bool
}

variable "enable_efs" {
  description = "Enable EFS file system for shared storage"
  type        = bool
}

variable "enable_ecr" {
  description = "Enable ECR repository for ephemeral Docker images"
  type        = bool
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs that need access to EFS"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
}

variable "prevent_destroy_optional_resources" {
  description = "Prevent destruction of durable optional resources such as EFS. ECR contains ephemeral runner images and is force-deleted by default."
  type        = bool
}

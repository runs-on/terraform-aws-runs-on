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

variable "cache_bucket_namespace" {
  description = "S3 namespace for the cache bucket. Use account-regional when an organization SCP requires account-regional S3 bucket names."
  type        = string
  default     = "global"

  validation {
    condition     = contains(["global", "account-regional"], var.cache_bucket_namespace)
    error_message = "Cache bucket namespace must be either global or account-regional."
  }
}

variable "cache_bucket_versioning_enabled" {
  description = "Enable S3 object versioning for the cache bucket."
  type        = bool
  default     = false
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

variable "ecr_pull_through_cache_rules" {
  description = "Existing ECR pull-through cache rules to reference for runner image pulls"
  type = map(object({
    ecr_repository_prefix      = string
    upstream_registry_url      = string
    upstream_repository_prefix = optional(string)
  }))
  default = {}
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

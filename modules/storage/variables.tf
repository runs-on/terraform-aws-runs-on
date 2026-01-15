# modules/storage/variables.tf
# Input variables for the storage module

variable "stack_name" {
  description = "Name of the RunsOn stack (used for resource naming)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.stack_name))
    error_message = "Stack name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cost_allocation_tag" {
  description = "Name of the tag key used for cost allocation"
  type        = string
}

variable "cache_expiration_days" {
  description = "Number of days to retain cache artifacts before expiration"
  type        = number

  validation {
    condition     = var.cache_expiration_days >= 1 && var.cache_expiration_days <= 365
    error_message = "Cache expiration days must be between 1 and 365."
  }
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
}

variable "force_destroy_buckets" {
  description = "Allow S3 buckets to be destroyed even when not empty. Set to false for production environments to prevent accidental data loss."
  type        = bool
}

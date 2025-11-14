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
  default     = "CostCenter"
}

variable "cache_expiration_days" {
  description = "Number of days to retain cache artifacts before expiration"
  type        = number
  default     = 30

  validation {
    condition     = var.cache_expiration_days >= 1 && var.cache_expiration_days <= 365
    error_message = "Cache expiration days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Additional tags to apply to all storage resources"
  type        = map(string)
  default     = {}
}

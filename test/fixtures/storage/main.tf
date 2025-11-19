module "storage" {
  source = "../../../modules/storage"

  stack_name            = var.stack_name
  cache_expiration_days = var.cache_expiration_days
  cost_allocation_tag   = var.cost_allocation_tag
}

variable "stack_name" {
  description = "Name of the stack for testing"
  type        = string
}

variable "cache_expiration_days" {
  description = "Number of days before cache expires"
  type        = number
  default     = 1
}

variable "cost_allocation_tag" {
  description = "Tag key for cost allocation"
  type        = string
  default     = "test-cost-center"
}

output "config_bucket_name" {
  description = "Name of the config S3 bucket"
  value       = module.storage.config_bucket_name
}

output "config_bucket_arn" {
  description = "ARN of the config S3 bucket"
  value       = module.storage.config_bucket_arn
}

output "cache_bucket_name" {
  description = "Name of the cache S3 bucket"
  value       = module.storage.cache_bucket_name
}

output "cache_bucket_arn" {
  description = "ARN of the cache S3 bucket"
  value       = module.storage.cache_bucket_arn
}

output "logging_bucket_name" {
  description = "Name of the logging S3 bucket"
  value       = module.storage.logging_bucket_name
}

output "logging_bucket_arn" {
  description = "ARN of the logging S3 bucket"
  value       = module.storage.logging_bucket_arn
}

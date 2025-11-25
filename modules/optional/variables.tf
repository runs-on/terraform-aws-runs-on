# modules/optional/variables.tf
# Input variables for the optional module

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
  default     = "production"
}

variable "enable_efs" {
  description = "Enable EFS file system for shared storage"
  type        = bool
  default     = false
}

variable "enable_ecr" {
  description = "Enable ECR repository for ephemeral Docker images"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for EFS mount targets"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs that need access to EFS"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "prevent_destroy" {
  description = "Prevent destruction of EFS and ECR resources. Set to true for production environments."
  type        = bool
  default     = true
}

# modules/optional/variables.tf
# Input variables for the optional module

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
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
  description = "List of public subnet IDs for EFS mount targets"
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

variable "prevent_destroy" {
  description = "Prevent destruction of EFS and ECR resources. Set to true for production environments."
  type        = bool
}

variable "force_delete_ecr" {
  description = "Allow ECR repository to be deleted even when it contains images. Set to true for testing environments."
  type        = bool
}

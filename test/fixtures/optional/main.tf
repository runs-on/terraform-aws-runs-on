module "optional" {
  source = "../../../modules/optional"

  stack_name         = var.stack_name
  enable_efs         = var.enable_efs
  enable_ecr         = var.enable_ecr
  vpc_id             = var.vpc_id
  public_subnet_ids  = var.public_subnet_ids
  security_group_ids = var.security_group_ids
  environment        = var.environment
  tags               = var.tags
}

variable "stack_name" {
  description = "Name of the stack for testing"
  type        = string
}

variable "enable_efs" {
  description = "Enable EFS file system"
  type        = bool
  default     = false
}

variable "enable_ecr" {
  description = "Enable ECR repository"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for EFS"
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for EFS mount targets"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for EFS"
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
  default     = "test"
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

output "efs_id" {
  description = "EFS file system ID (empty if not enabled)"
  value       = var.enable_efs ? module.optional.efs_id : ""
}

output "efs_arn" {
  description = "EFS file system ARN (empty if not enabled)"
  value       = var.enable_efs ? module.optional.efs_arn : ""
}

output "ecr_repository_url" {
  description = "ECR repository URL (empty if not enabled)"
  value       = var.enable_ecr ? module.optional.ecr_repository_url : ""
}

output "ecr_repository_arn" {
  description = "ECR repository ARN (empty if not enabled)"
  value       = var.enable_ecr ? module.optional.ecr_repository_arn : ""
}

# variables.tf
# Root module variables

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "github_organization" {
  description = "GitHub organization or username"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "VPC ID where RunsOn will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for runners"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for runners"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for runners"
  type        = list(string)
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on"
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

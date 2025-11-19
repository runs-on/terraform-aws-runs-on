# EFS-Enabled Example Variables

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on-efs"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.19.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.19.1.0/24", "10.19.2.0/24", "10.19.3.0/24"]
}

# Required RunsOn Variables
variable "github_organization" {
  description = "GitHub organization or username for RunsOn integration"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

variable "email" {
  description = "Email address for cost and alert reports"
  type        = string
}

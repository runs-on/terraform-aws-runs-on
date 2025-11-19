# Full-Featured Example Variables

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on-full"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.21.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.21.1.0/24", "10.21.2.0/24", "10.21.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.21.10.0/24", "10.21.11.0/24", "10.21.12.0/24"]
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

# Basic Example Variables
# Only required variables are defined here

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.17.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.17.1.0/24", "10.17.2.0/24", "10.17.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (empty list = no private subnets)"
  type        = list(string)
  default     = []
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

# Private Networking Example Variables

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on-private"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.18.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.18.1.0/24", "10.18.2.0/24", "10.18.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (required for private networking)"
  type        = list(string)
  default     = ["10.18.10.0/24", "10.18.11.0/24", "10.18.12.0/24"]
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

# Feature-specific: Private Networking
variable "private_mode" {
  description = "Private networking mode: 'false', 'true', 'always', or 'only'"
  type        = string
  default     = "true"

  validation {
    condition     = contains(["false", "true", "always", "only"], var.private_mode)
    error_message = "Private mode must be one of: false, true, always, only."
  }
}

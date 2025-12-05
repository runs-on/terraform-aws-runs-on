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
  default     = ["10.21.0.0/20", "10.21.16.0/20", "10.21.32.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.21.128.0/20", "10.21.144.0/20", "10.21.160.0/20"]
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

# Optional: Monitoring and Alerting
variable "enable_dashboard" {
  description = "Create a CloudWatch dashboard for monitoring RunsOn operations"
  type        = bool
  default     = false
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for alert notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

# Resource Protection
variable "prevent_destroy_optional_resources" {
  description = "Prevent accidental deletion of EFS and ECR resources"
  type        = bool
  default     = true
}

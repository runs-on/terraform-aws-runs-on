variable "aws_region" {
  description = "AWS region for test resources"
  type        = string
  default     = "us-east-1"
}

variable "test_id" {
  description = "Unique test identifier for resource naming"
  type        = string
}

variable "enable_nat" {
  description = "Enable NAT gateway for private subnet internet access"
  type        = bool
  default     = false
}

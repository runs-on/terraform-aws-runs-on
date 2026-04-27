variable "stack_name" {
  description = "Stack name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Explicit runner security groups"
  type        = list(string)
}

variable "private_mode" {
  description = "Private networking mode"
  type        = string
}

variable "ssh_allowed" {
  description = "Allow SSH to runner instances"
  type        = bool
}

variable "ssh_cidr_range" {
  description = "SSH CIDR range for auto-created security groups"
  type        = string
}

variable "tags" {
  description = "Tags applied to networking resources"
  type        = map(string)
}

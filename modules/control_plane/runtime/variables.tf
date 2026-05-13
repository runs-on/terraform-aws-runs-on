variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "stack_name" {
  description = "Stack name"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "service_name" {
  description = "ECS service name"
  type        = string
}

variable "task_definition_family" {
  description = "Task definition family"
  type        = string
}

variable "execution_role_name" {
  description = "Execution role name"
  type        = string
}

variable "task_role_name" {
  description = "Shared ECS task role name"
  type        = string
}

variable "task_policy_name" {
  description = "Inline policy name for the shared ECS task role"
  type        = string
}

variable "runner_instance_role_arn" {
  description = "Runner EC2 role ARN"
  type        = string
}

variable "cache_bucket_arn" {
  description = "Cache bucket ARN"
  type        = string
}

variable "ebs_encryption_key_id" {
  description = "Optional EBS encryption key ID"
  type        = string
  default     = ""
}

variable "extra_task_role_statements" {
  description = "Additional IAM statements appended to the shared task role policy"
  type        = any
  default     = []
}

variable "extra_execution_role_statements" {
  description = "Additional IAM statements appended to the ECS task execution role policy"
  type        = any
  default     = []
}

variable "task_role_managed_policy_arns" {
  description = "Managed policy ARNs attached to the shared task role"
  type        = list(string)
  default     = []
}

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
}

variable "log_retention_days" {
  description = "Runtime log retention in days"
  type        = number
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
}

variable "memory" {
  description = "Task memory in MiB"
  type        = number
}

variable "container_definitions" {
  description = "ECS container definitions"
  type        = any
}

variable "desired_count" {
  description = "Desired ECS service count"
  type        = number
}

variable "capacity_provider" {
  description = "ECS capacity provider used by the service"
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.capacity_provider)
    error_message = "capacity_provider must be one of: FARGATE, FARGATE_SPOT."
  }
}

variable "force_new_deployment" {
  description = "Force a new ECS deployment of the worker service."
  type        = bool
  default     = false
}

variable "assign_public_ip" {
  description = "Assign public IPs to tasks"
  type        = bool
}

variable "security_group_ids" {
  description = "Task security groups"
  type        = list(string)
}

variable "subnet_ids" {
  description = "Task subnet IDs"
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to runtime resources"
  type        = map(string)
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy deployment percentage"
  type        = number
  default     = 0
}

variable "deployment_maximum_percent" {
  description = "Maximum deployment percentage"
  type        = number
  default     = 200
}

variable "platform_version" {
  description = "Fargate platform version"
  type        = string
  default     = "LATEST"
}

variable "container_insights_enabled" {
  description = "Enable ECS container insights on the cluster"
  type        = bool
  default     = true
}

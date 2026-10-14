variable "stack_name" {
  description = "RunsOn stack name used to name alerting resources."
  type        = string
}

variable "account_id" {
  description = "AWS account ID allowed to publish AWS Budget notifications."
  type        = string
}

variable "email" {
  description = "Email address for alerts and notifications."
  type        = string

  validation {
    condition     = trimspace(var.email) != ""
    error_message = "email must not be empty."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alert notifications."
  type        = string
  default     = ""
  sensitive   = true
}

variable "daily_budget_usd" {
  description = "Daily AWS cost budget in USD for the stack, notifying the alert topic when actual cost exceeds it. Set to 0 to disable the budget."
  type        = number
  default     = 0
}

variable "cost_allocation_tag" {
  description = "Cost allocation tag key whose value is the stack name; the daily budget filters on it."
  type        = string
  default     = "stack"
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for alert topic server-side encryption. Empty leaves SSE off (SNS default disk encryption only)."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for the Slack webhook Lambda."
  type        = number
  default     = 14
}

variable "permission_boundary_arn" {
  description = "Optional IAM permissions boundary ARN applied to alerting roles"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to alerting resources."
  type        = map(string)
}

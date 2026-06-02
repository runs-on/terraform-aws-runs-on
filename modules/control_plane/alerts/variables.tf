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

variable "allow_budgets_publish" {
  description = "Allow AWS Budgets in this account to publish to the alert topic."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to alerting resources."
  type        = map(string)
}

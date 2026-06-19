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

variable "slack_bot_token" {
  description = "Slack bot token (xoxb-...) for alert notifications via chat.postMessage. Takes precedence over slack_webhook_url when both are set. Requires slack_channel_id."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_channel_id" {
  description = "Slack channel ID or name to post alerts to when slack_bot_token is set (e.g. C0123ABCD or #channel)."
  type        = string
  default     = ""
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

# Input variables for the RunsOn Flex control plane module

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cost_allocation_tag" {
  description = "Tag key for cost allocation"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key"
  type        = string
  sensitive   = true
}

variable "network" {
  description = "Shared runner networking resources"
  type = object({
    vpc_id             = string
    private_mode       = string
    public_subnet_ids  = list(string)
    private_subnet_ids = list(string)
    security_group_ids = list(string)
  })
}

variable "extras" {
  description = "Shared runner extras resources"
  type = object({
    cache = object({
      bucket_id   = string
      bucket_name = string
      bucket_arn  = string
    })
    efs = object({
      enabled           = bool
      file_system_id    = string
      file_system_arn   = string
      file_system_dns   = string
      security_group_id = string
    })
    ecr = object({
      enabled         = bool
      repository_arn  = string
      repository_name = string
      repository_url  = string
    })
  })
}

variable "compute" {
  description = "Shared runner compute resources"
  type = object({
    runner_iam = object({
      role_arn     = string
      role_name    = string
      role_id      = string
      profile_arn  = string
      profile_name = string
    })
    runner_logs = object({
      group_name          = string
      group_arn           = string
      resource_group_name = string
      resource_group_arn  = string
    })
    launch_templates = object({
      linux_default = object({
        id             = string
        latest_version = number
      })
      linux_default_nested = object({
        id             = string
        latest_version = number
      })
      windows_default = object({
        id             = string
        latest_version = number
      })
      windows_default_nested = object({
        id             = string
        latest_version = number
      })
      linux_private = object({
        id             = string
        latest_version = number
      })
      linux_private_nested = object({
        id             = string
        latest_version = number
      })
      windows_private = object({
        id             = string
        latest_version = number
      })
      windows_private_nested = object({
        id             = string
        latest_version = number
      })
    })
  })
}

variable "github" {
  description = "GitHub settings and optional declarative app secret payload"
  type = object({
    organization   = string
    enterprise_url = string
    api_strategy   = string
    apps           = any
  })
}

variable "runtime" {
  description = "Flex runtime settings"
  type = object({
    image                     = string
    tag                       = string
    maintenance_mode          = bool
    size                      = string
    capacity_provider         = string
    force_new_deployment      = bool
    private_mode              = string
    ecr_repository_url        = string
    custom_policy_arn         = string
    otel_exporter_endpoint    = string
    otel_exporter_headers     = string
    otel_exporter_temporality = string
    otel_logs_enabled         = bool
    otel_traces_enabled       = bool
    logger_level              = string
    extra_env_vars            = map(string)
  })
}

variable "runner" {
  description = "Flex EC2 runner settings published into stack config"
  type = object({
    ssh_allowed              = bool
    ebs_encryption_key_id    = string
    max_runtime              = number
    config_auto_extends_from = string
    custom_tags              = list(string)
  })
}

variable "operations" {
  description = "Flex operational controls and integrations"
  type = object({
    app_budget_daily_usd              = number
    enable_cost_reports               = bool
    spot_circuit_breaker              = string
    integration_step_security_api_key = string
    enable_admin_routes               = bool
    enable_waf                        = bool
    public_ingress_web_acl_arn        = string
  })
}

variable "alerts" {
  description = "Flex alert delivery settings"
  type = object({
    email             = string
    slack_webhook_url = string
  })

  validation {
    condition     = trimspace(var.alerts.email) != ""
    error_message = "alerts.email must not be empty."
  }
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "stack_name" {
  description = "Fleet stack name"
  type        = string
}

variable "github" {
  description = "GitHub authentication and host settings for the Fleet runtime"
  type = object({
    app_id          = any
    app_private_key = any
    enterprise_pat  = any
    base_url        = string
    enterprise      = any
    license_key     = string
  })
  sensitive = true
}

variable "alerts" {
  description = "Fleet alert delivery settings"
  type = object({
    email             = string
    slack_webhook_url = string
  })

  validation {
    condition     = trimspace(var.alerts.email) != ""
    error_message = "alerts.email must not be empty."
  }
}

variable "catalog" {
  description = "Runner image, runner, and fleet catalogs"
  type = object({
    images  = map(any)
    runners = map(any)
    fleets  = map(any)
  })
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

variable "tags" {
  description = "Tags applied to Fleet resources"
  type        = map(string)
}

variable "runtime" {
  description = "Fleet ECS runtime settings"
  type = object({
    image                     = string
    size                      = string
    capacity_provider         = string
    maintenance_mode          = bool
    log_retention_days        = number
    otel_exporter_endpoint    = string
    otel_exporter_headers     = string
    otel_exporter_temporality = string
    otel_logs_enabled         = bool
    otel_traces_enabled       = bool
    extra_env_vars            = map(string)
  })
}

variable "integration_step_security_api_key" {
  description = "API key for StepSecurity integration forwarded to runner agents"
  type        = string
  sensitive   = true
}

variable "control_plane" {
  description = "Fleet control plane settings published into the runtime secret"
  type = object({
    environment          = string
    private_mode         = string
    cost_allocation_tag  = string
    app_tag              = string
    runner_custom_tags   = list(string)
    spot_circuit_breaker = optional(string, "")
  })
}

variable "enable_cache_isolation" {
  description = "Vend brokered, per-repository credentials for Magic Cache data under scoped-cache/*. The always-created broker stays idle when false; direct cache/* access is stack-shared in both modes"
  type        = bool
  default     = false
}

variable "diagnostic_settings" {
  description = "Non-sensitive stack settings exposed by the job diagnostics resolver"
  type        = any
  default     = {}
}

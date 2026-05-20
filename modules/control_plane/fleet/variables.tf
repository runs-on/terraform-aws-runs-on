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
  })
  sensitive = true
}

variable "catalog" {
  description = "Runner image, runner, and pool catalogs"
  type = object({
    images  = map(any)
    runners = map(any)
    pools   = map(any)
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

variable "enable_dynamodb_pitr" {
  description = "Enable point-in-time recovery (PITR) on the Fleet control plane DynamoDB tables"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to Fleet resources"
  type        = map(string)
}

variable "runtime" {
  description = "Fleet ECS runtime settings"
  type = object({
    image              = string
    size               = string
    log_retention_days = number
    extra_env_vars     = map(string)
  })
}

variable "control_plane" {
  description = "Fleet control plane settings published into the runtime secret"
  type = object({
    environment         = string
    private_mode        = string
    cost_allocation_tag = string
    app_tag             = string
    runner_custom_tags  = list(string)
  })
}

variable "stack_name" {
  description = "Name of the RunsOn Fleet stack."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.stack_name) != "" && can(regex("^[a-z0-9-]+$", var.stack_name))
    error_message = "Stack name must be set and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "github_app_id" {
  description = "GitHub App ID used by the Fleet runtime."
  type        = number
  default     = null
}

variable "github_app_private_key" {
  description = "GitHub App private key in PEM format."
  type        = string
  sensitive   = true
  default     = null
}

variable "github_enterprise_pat" {
  description = "Classic PAT used for enterprise-target Fleet mode. Must start with ghp_ when set."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.github_enterprise_pat == null ? true : startswith(var.github_enterprise_pat, "ghp_")
    error_message = "github_enterprise_pat must start with ghp_ when set."
  }
}

variable "github_base_url" {
  description = "GitHub host root URL. Leave the default for github.com and set a GHES host root such as https://ghe.example.com when needed."
  type        = string
  default     = "https://github.com"
}

variable "github_enterprise_name" {
  description = "GitHub Enterprise slug used when github_enterprise_pat is set."
  type        = string
  default     = null
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name used by the workflow targeting contract."
  type        = string
  default     = "production"
}

variable "images" {
  description = "Custom runner image catalog keyed by image name. Built-in image names such as ubuntu24-full-x64 do not need entries here."
  type        = map(any)
  default     = {}
}

variable "runners" {
  description = "Runner catalog keyed by runner name. Entries must follow the shared config module contract."
  type        = map(any)
}

variable "fleets" {
  description = "Fleet catalog keyed by fleet name. Entries use the shared runner shape plus Fleet-specific settings."
  type        = map(any)
}

variable "vpc_id" {
  description = "VPC ID where the Fleet stack will run."
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier (vpc-*)."
  }
}

variable "public_subnet_ids" {
  description = "Public subnet IDs used for runners and Fargate when private_mode=false."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 1
    error_message = "At least one public subnet ID is required."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used for Fargate and runners when private_mode is enabled."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for runners and the Fleet worker. Leave empty to create a dedicated group."
  type        = list(string)
  default     = []
}

variable "private_mode" {
  description = "Private networking mode: false, true, always, or only."
  type        = string
  default     = "false"

  validation {
    condition     = contains(["false", "true", "always", "only"], var.private_mode)
    error_message = "Private mode must be one of: false, true, always, only."
  }
}

variable "ssh_allowed" {
  description = "Allow SSH ingress when the module creates its own security group."
  type        = bool
  default     = true
}

variable "ssh_cidr_range" {
  description = "CIDR range allowed for SSH access when the module creates its own security group."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_cidr_range, 0))
    error_message = "ssh_cidr_range must be a valid IPv4 CIDR block."
  }
}

variable "cost_allocation_tag" {
  description = "Tag key used for cost allocation."
  type        = string
  default     = "stack"
}

variable "tags" {
  description = "Additional tags applied to all created AWS resources."
  type        = map(string)
  default     = {}
}

variable "runtime_image" {
  description = "RunsOn worker image containing the fleetd binary. Override with a runs-on-ci image for live validation."
  type        = string
  default     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:v3.1.0-rc.1@sha256:d2bc67e1ec8424bd1b30986426ad6f5b3af59c79c69f7109af6384b4f7a6c998"
}

variable "extra_env_vars" {
  description = "Additional environment variables to set on the Fleet worker service."
  type        = map(string)
  default     = {}
}

variable "integration_step_security_api_key" {
  description = "API key for StepSecurity integration (optional)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "app_size" {
  description = "Preset for the Fleet worker service, default EC2 launch concurrency, and default registration concurrency. Allowed values: small, medium, high, xhigh."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "high", "xhigh"], var.app_size)
    error_message = "app_size must be one of: small, medium, high, xhigh."
  }
}

variable "app_capacity_provider" {
  description = "Fargate capacity provider for the Fleet worker service. Use fargate_spot to lower idle cost for small installs; interrupted in-flight assigned jobs are reconciled by the Fleet runtime."
  type        = string
  default     = "fargate"

  validation {
    condition     = contains(["fargate", "fargate_spot"], var.app_capacity_provider)
    error_message = "app_capacity_provider must be one of: fargate, fargate_spot."
  }
}

variable "maintenance_mode" {
  description = "Enable maintenance mode (disables queue processing and leader election)"
  type        = bool
  default     = false
}

variable "bootstrap_tag" {
  description = "Bootstrap release tag used by the shared compute bootstrap template."
  type        = string
  default     = "v0.1.17"
}

variable "app_tag" {
  description = "Application/agent tag published into the cache bucket and passed to runners."
  type        = string
  default     = "v3.1.0-rc.1"
}

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes passed to the shared compute bootstrap template."
  type        = number
  default     = 60
}

variable "cache_expiration_days" {
  description = "Number of days to retain cache artifacts."
  type        = number
  default     = 10

  validation {
    condition     = var.cache_expiration_days >= 1 && var.cache_expiration_days <= 365
    error_message = "Cache expiration days must be between 1 and 365."
  }
}

variable "force_destroy_buckets" {
  description = "Allow the cache bucket to be destroyed while non-empty."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "permission_boundary_arn" {
  description = "Optional IAM permission boundary ARN applied to created roles."
  type        = string
  default     = ""
}

variable "runner_custom_policy_arn" {
  description = "Optional managed policy attached to the EC2 runner role."
  type        = string
  default     = ""
}

variable "enable_bedrock" {
  description = "Enable Amazon Bedrock access for EC2 runner instances."
  type        = bool
  default     = false
}

variable "ipv6_enabled" {
  description = "Enable IPv6 on EC2 runner launch templates."
  type        = bool
  default     = false
}

variable "runner_custom_tags" {
  description = "Additional custom tags propagated to launched runner instances."
  type        = list(string)
  default     = []
}

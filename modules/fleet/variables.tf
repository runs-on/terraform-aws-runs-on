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

variable "email" {
  description = "Email address for alerts and notifications (requires confirmation)"
  type        = string

  validation {
    condition     = trimspace(var.email) != ""
    error_message = "email must not be empty."
  }
}

variable "alert_slack_webhook_url" {
  description = "Slack webhook URL for alert notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "environment" {
  description = "Environment name used by the workflow targeting contract."
  type        = string
  default     = "production"
}

variable "images" {
  description = "Custom runner image catalog keyed by image name. Built-in image names such as ubuntu24-full-x64 and ubuntu26-full-x64 do not need entries here."
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

variable "spot_circuit_breaker" {
  description = "Spot circuit breaker for Fleet launches, formatted as COUNT/WINDOW_MINUTES/RECOVERY_MINUTES: after COUNT spot interruptions within WINDOW_MINUTES, launch on-demand for RECOVERY_MINUTES. \"false\" disables it; empty uses the built-in default \"2/15/30\" (same semantics as the Flex SpotCircuitBreaker stack parameter)."
  type        = string
  default     = ""
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
  description = "Public subnet IDs used for runners and Fargate. Required unless private_mode is \"only\"."
  type        = list(string)
  default     = []
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
  default     = false
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
  default     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:v3.2.2-rc.1@sha256:e9bb583a491090ca376a0f5426de5f950ed4a7fac41de8be7777e8a8d0d5c8da"
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

variable "otel_exporter_endpoint" {
  description = "OpenTelemetry exporter endpoint for observability (optional)"
  type        = string
  default     = ""
}

variable "otel_exporter_headers" {
  description = "OpenTelemetry exporter headers (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "otel_exporter_temporality" {
  description = "OTLP metrics temporality: cumulative (default) or delta"
  type        = string
  default     = "cumulative"

  validation {
    condition     = contains(["cumulative", "delta"], var.otel_exporter_temporality)
    error_message = "OTLP temporality must be one of: cumulative, delta."
  }
}

variable "otel_logs_enabled" {
  description = "Enable OpenTelemetry log export"
  type        = bool
  default     = true
}

variable "otel_traces_enabled" {
  description = "Enable OpenTelemetry trace export"
  type        = bool
  default     = true
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
  description = "Application/agent tag published into the cache bucket and passed to runners. Passing null falls back to the default, which release publication pins to the released version."
  type        = string
  default     = "v3.2.2-rc.1"
  nullable    = false
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

variable "cache_bucket_namespace" {
  description = "S3 namespace for the cache bucket. Use account-regional when an organization SCP requires account-regional S3 bucket names."
  type        = string
  default     = "global"

  validation {
    condition     = contains(["global", "account-regional"], var.cache_bucket_namespace)
    error_message = "Cache bucket namespace must be either global or account-regional."
  }
}

variable "cache_bucket_versioning_enabled" {
  description = "Enable S3 object versioning for the cache bucket."
  type        = bool
  default     = false
}

variable "force_destroy_buckets" {
  description = "Allow the cache bucket to be destroyed while non-empty."
  type        = bool
  default     = false
}

variable "enable_ecr" {
  description = "Enable an ECR repository for ephemeral Docker image and BuildKit cache storage."
  type        = bool
  default     = false
}

variable "ecr_pull_through_cache_rules" {
  description = "Existing ECR pull-through cache rules to reference for Fleet runner image pulls. Create or import the regional rules outside the RunsOn module."
  type = map(object({
    ecr_repository_prefix      = string
    upstream_registry_url      = string
    upstream_repository_prefix = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, rule in var.ecr_pull_through_cache_rules :
      trimspace(rule.ecr_repository_prefix) != "" && trimspace(rule.upstream_registry_url) != ""
    ])
    error_message = "Each ECR pull-through cache rule reference requires non-empty ecr_repository_prefix and upstream_registry_url values."
  }

  validation {
    condition = length(distinct([
      for key, rule in var.ecr_pull_through_cache_rules :
      trimspace(rule.ecr_repository_prefix)
    ])) == length(var.ecr_pull_through_cache_rules)
    error_message = "ECR pull-through cache rule ecr_repository_prefix values must be unique."
  }

  validation {
    condition = alltrue([
      for _, rule in var.ecr_pull_through_cache_rules :
      upper(trimspace(rule.ecr_repository_prefix)) != "ROOT"
    ])
    error_message = "The ROOT ecr_repository_prefix is not supported: it would grant runners access to every ECR repository in the account. Use a named prefix such as \"docker-hub\"; Docker Hub mirroring stays transparent via the runner-local registry mirror."
  }

  validation {
    condition = length([
      for _, rule in var.ecr_pull_through_cache_rules : rule
      if lower(trimspace(rule.upstream_registry_url)) == "registry-1.docker.io" && try(trimspace(rule.upstream_repository_prefix), "") == ""
    ]) <= 1
    error_message = "At most one Docker Hub pull-through cache rule without an upstream_repository_prefix may configure transparent runner-local mirroring."
  }
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

variable "runner_custom_policy_arns" {
  description = "Optional managed policy ARNs attached to the EC2 runner role. Use this when policy ARNs are computed by other resources."
  type        = list(string)
  default     = []
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

variable "enable_cache_isolation" {
  description = "Enable brokered, per-repository/per-branch credentials for Magic Cache data under scoped-cache/*. Direct S3 cache integrations keep instance-profile access to the stack-shared cache/* namespace and are not repository-isolated. Opt-in"
  type        = bool
  default     = false
}

variable "enable_stickydisk_isolation" {
  description = "Remove the legacy EBS volume/snapshot permissions from the runner instance role, so all sticky-disk EBS operations happen exclusively on the control plane. Breaks the legacy v1 runs-on/snapshot action. Opt-in"
  type        = bool
  default     = false
}

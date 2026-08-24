# variables.tf
# Root module variables for RunsOn infrastructure
# Organized by submodule usage for clarity

###########################
# Shared Configuration
# Variables used across multiple modules
###########################

variable "stack_name" {
  description = "Name for the RunsOn stack (used for resource naming)"
  type        = string
  default     = "runs-on"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.stack_name))
    error_message = "Stack name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name used for resource tagging and RunsOn job filtering. RunsOn will only process jobs with an 'env' label matching this value. See https://runs-on.com/configuration/environments/ for details."
  type        = string
  default     = "production"
}

variable "cost_allocation_tag" {
  description = "Name of the tag key used for cost allocation and tracking"
  type        = string
  default     = "stack"
}

variable "tags" {
  description = "Tags to apply to all resources. Note: 'runs-on-stack-name' is added automatically for resource discovery."
  type        = map(string)
  default     = {}
}

###########################
# GitHub Configuration
# Used by: core module
###########################

variable "github_organization" {
  description = "GitHub organization or username for RunsOn integration"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.github_organization))
    error_message = "GitHub organization must contain only alphanumeric characters and hyphens."
  }
}

variable "github_enterprise_url" {
  description = "GitHub Enterprise Server URL (optional, leave empty for github.com)"
  type        = string
  default     = ""
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

###########################
# Networking Configuration
# Used by: core, compute, optional modules
###########################

variable "vpc_id" {
  description = "VPC ID where RunsOn infrastructure will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier (vpc-*)."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for runner instances. Required unless private_mode is \"only\"."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for runner instances (required if private_mode is not 'false')"
  type        = list(string)
  default     = []
}

variable "private_mode" {
  description = "Private networking mode: 'false' (disabled), 'true' (opt-in with label), 'always' (default with opt-out), 'only' (forced, no public option)"
  type        = string
  default     = "false"

  validation {
    condition     = contains(["false", "true", "always", "only"], var.private_mode)
    error_message = "Private mode must be one of: false, true, always, only."
  }
}

variable "private_mode_delay" {
  description = "Delay before starting the worker service in private mode, to allow NAT gateways to become ready. Set to \"60s\" or higher for fresh NAT gateway deployments."
  type        = string
  default     = "0s"
}

variable "security_group_ids" {
  description = "Security group IDs for runner instances and the worker service. If empty list provided, security groups will be created automatically."
  type        = list(string)
  default     = []
}

variable "ssh_allowed" {
  description = "Allow SSH access to runner instances"
  type        = bool
  default     = false
}

variable "ssh_cidr_range" {
  description = "CIDR range allowed for SSH access to runner instances (only applies if ssh_allowed is true)"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_cidr_range, 0))
    error_message = "ssh_cidr_range must be a valid IPv4 CIDR block."
  }
}

###########################
# Storage Configuration
# Used by: storage module
###########################

variable "cache_expiration_days" {
  description = "Number of days to retain cache artifacts in S3 before expiration"
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

variable "locks_table_point_in_time_recovery_enabled" {
  description = "Enable DynamoDB point-in-time recovery for the transient locks table. This can help satisfy backup and compliance requirements, but incurs additional storage costs."
  type        = bool
  default     = false
}

variable "force_destroy_buckets" {
  description = "Allow S3 buckets to be destroyed even when not empty. Set to false for production environments to prevent accidental data loss."
  type        = bool
  default     = false
}

###########################
# Compute Configuration
# Used by: compute module
###########################

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs for EC2 instances"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "permission_boundary_arn" {
  description = "IAM permissions boundary ARN to attach to all IAM roles (optional)"
  type        = string
  default     = ""
}

variable "ipv6_enabled" {
  description = "Enable IPv6 support for runner instances"
  type        = bool
  default     = false
}

variable "ebs_encryption_key_id" {
  description = "KMS key ID for explicit EBS volume encryption. Leave empty to omit explicit EBS encryption fields, use alias/aws/ebs for the AWS-managed EBS key, or provide a customer-managed key ID, alias, or ARN. Prefer a full ARN for customer-managed keys, especially cross-account keys. Customer-managed keys must also trust the generated RunsOn worker task role in their key policy."
  type        = string
  default     = ""
}

###########################
# Worker Service Configuration
# Used by: core module
###########################

variable "app_image" {
  description = "Container image for the RunsOn worker service. Published module releases inject a pinned public default during mirror publication."
  type        = string
  default     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:v3.2.3@sha256:6c2d5ede8996d875578e2fd6a5f472f89a75c7773525f1c747ec333065425e73"
  nullable    = false
}

variable "app_tag" {
  description = "Application version tag for RunsOn service. Published module releases inject the released default during mirror publication."
  type        = string
  default     = "v3.2.3"
  nullable    = false
}

variable "bootstrap_tag" {
  description = "Bootstrap script version tag"
  type        = string
  default     = "v0.1.12"
}

variable "maintenance_mode" {
  description = "Enable maintenance mode (disables queue processing and leader election)"
  type        = bool
  default     = false
}

variable "app_size" {
  description = "Preset for the worker service, default EC2 launch concurrency, and default registration concurrency. Allowed values: small, medium, high, xhigh."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "high", "xhigh"], var.app_size)
    error_message = "app_size must be one of: small, medium, high, xhigh."
  }
}

variable "app_capacity_provider" {
  description = "Fargate capacity provider for the RunsOn worker service. Use fargate_spot to lower idle cost for small installs; interrupted in-flight queue messages retry after the SQS visibility timeout."
  type        = string
  default     = "fargate"

  validation {
    condition     = contains(["fargate", "fargate_spot"], var.app_capacity_provider)
    error_message = "app_capacity_provider must be one of: fargate, fargate_spot."
  }
}

variable "app_force_new_deployment" {
  description = "Force a new ECS deployment of the RunsOn control-plane service. Set to true for one apply when migrating existing installs across the v3.0.6 ECS capacity provider change or when changing app_capacity_provider."
  type        = bool
  default     = false
}

variable "app_ecr_repository_url" {
  description = "Private ECR repository URL for RunsOn image (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo:tag). When specified, the worker service will pull from this private ECR instead of public ECR."
  type        = string
  default     = ""
}

variable "app_custom_policy_arns" {
  description = "Optional managed IAM policy ARNs to attach to the RunsOn service role."
  type        = list(string)
  default     = []
}

variable "github_app_id" {
  description = "GitHub App ID. If provided along with other github_app_* variables, creates a Secrets Manager secret and skips the web-based GitHub App setup flow."
  type        = number
  default     = null
}

variable "github_app_private_key" {
  description = "GitHub App private key (PEM format)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_app_webhook_secret" {
  description = "GitHub App webhook secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_app_client_id" {
  description = "GitHub App client ID"
  type        = string
  default     = ""
}

variable "github_app_client_secret" {
  description = "GitHub App client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_api_boost_apps" {
  description = "Additional same-org GitHub Apps used only for API boost capacity. These entries omit webhook secrets and are written under the shared GitHub apps secret."
  type = map(object({
    github_app_id            = number
    github_app_private_key   = string
    github_app_client_id     = string
    github_app_client_secret = string
    github_app_label         = optional(string, "")
  }))
  default   = {}
  sensitive = true
}

###########################
# Runner Configuration
# Used by: core module
###########################

variable "github_api_strategy" {
  description = "Strategy for GitHub API calls (normal, conservative)"
  type        = string
  default     = "normal"

  validation {
    condition     = contains(["normal", "conservative"], var.github_api_strategy)
    error_message = "GitHub API strategy must be one of: normal, conservative."
  }
}

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes for runners before forced termination"
  type        = number
  default     = 720

  validation {
    condition     = var.runner_max_runtime >= 1
    error_message = "Runner max runtime must be at least 1 minute."
  }
}

variable "runner_custom_policy_arns" {
  description = "Optional managed IAM policy ARNs to attach to the EC2 runner instance role. Use this when policy ARNs are computed by other resources."
  type        = list(string)
  default     = []
}

variable "runner_config_auto_extends_from" {
  description = "Auto-extend runner configuration from this base config"
  type        = string
  default     = ".github-private"
}

variable "runner_custom_tags" {
  description = "Custom tags to apply to runner instances (comma-separated list)"
  type        = list(string)
  default     = []
}

###########################
# Operational Configuration
# Used by: core module
###########################

variable "enable_cost_reports" {
  description = "Cost report email cadence: no, daily, weekly, or monthly. Legacy true/false values must be replaced with daily/no when upgrading."
  type        = string
  default     = "daily"

  validation {
    condition     = contains(["no", "daily", "weekly", "monthly"], var.enable_cost_reports)
    error_message = "enable_cost_reports must be one of: no, daily, weekly, monthly."
  }
}

variable "spot_circuit_breaker" {
  description = "Spot instance circuit breaker configuration (e.g., '2/15/30' = 2 failures in 15min, block for 30min)"
  type        = string
  default     = "2/15/30"
}

###########################
# Monitoring & Budgets
# Used by: core module
###########################

variable "app_budget_daily_usd" {
  description = "Daily AWS cost budget in USD for this stack, filtered by the configured cost allocation tag. Set to 0 to disable the budget. For AWS Organizations member accounts, activate the cost allocation tag in the management account's Billing settings."
  type        = number
  default     = 10
}

variable "enable_default_dashboard" {
  description = "Create the default RunsOn CloudWatch dashboard. Set to false when managing a custom dashboard separately."
  type        = bool
  default     = true
}

###########################
# Integration Configuration
# Used by: core module
###########################

variable "integration_step_security_api_key" {
  description = "API key for StepSecurity integration (optional)"
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

variable "logger_level" {
  description = "Logging level for RunsOn service (debug, info, warn, error)"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.logger_level)
    error_message = "Logger level must be one of: debug, info, warn, error."
  }
}

###########################
# Extra Environment Variables
# Used by: core module
###########################

variable "extra_env_vars" {
  description = "Additional environment variables to set on the worker service"
  type        = map(string)
  default     = {}
}

###########################
# Alert Configuration
# Used by: core module
###########################

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

###########################
# Optional Features
# Used by: optional module
###########################

variable "mandatory_extras" {
  description = "Runner extras (e.g. s3-cache, otel) that are always enabled for every runner, regardless of label or repo config overrides."
  type        = list(string)
  default     = []
}

variable "enable_efs" {
  description = "Enable EFS file system for shared storage across runners"
  type        = bool
  default     = false
}

variable "enable_ecr" {
  description = "Enable ECR repository for ephemeral Docker image storage"
  type        = bool
  default     = false
}

variable "ecr_pull_through_cache_rules" {
  description = "Existing ECR pull-through cache rules to reference for runner image pulls. Create or import the regional rules outside the RunsOn module."
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

variable "enable_bedrock" {
  description = "Enable Amazon Bedrock access for EC2 runner instances."
  type        = bool
  default     = false
}

variable "prevent_destroy_optional_resources" {
  description = "Prevent destruction of durable optional resources such as EFS. ECR contains ephemeral runner images and is force-deleted by default."
  type        = bool
  default     = true
}

###########################
# WAF Configuration
# Used by: core module
###########################

variable "enable_waf" {
  description = "Enable AWS WAF for the public ingress"
  type        = bool
  default     = false
}

variable "enable_admin_routes" {
  description = "Enable the admin Lambda routes (`/`, `/setup`, `/setup/{proxy+}`, `/readyz`) on the public ingress"
  type        = bool
  default     = true
}

variable "public_ingress_web_acl_arn" {
  description = "Optional user-managed AWS WAFv2 Web ACL ARN to associate with the public ingress. When set, RunsOn will not manage webhook IP synchronization."
  type        = string
  default     = ""
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

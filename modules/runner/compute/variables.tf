variable "region" {
  description = "AWS region where resources are deployed"
  type        = string
}

variable "account_id" {
  description = "AWS account ID for resource ARN construction"
  type        = string
}

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "cost_allocation_tag" {
  description = "Tag key for cost allocation"
  type        = string
}

variable "network" {
  description = "Runner networking resources"
  type = object({
    vpc_id             = string
    private_mode       = string
    public_subnet_ids  = list(string)
    private_subnet_ids = list(string)
    security_group_ids = list(string)
  })
}

variable "extras" {
  description = "Runner extras including cache, EFS, and ECR resources"
  type = object({
    cache = object({
      bucket_id   = string
      bucket_arn  = string
      bucket_name = string
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
    pull_through_cache = object({
      enabled           = bool
      registry_url      = string
      docker_hub_prefix = string
      rules = map(object({
        ecr_repository_prefix      = string
        upstream_registry_url      = string
        upstream_repository_prefix = string
      }))
    })
  })
}

variable "log_retention_days" {
  description = "Days to retain CloudWatch logs"
  type        = number
}

variable "permission_boundary_arn" {
  description = "IAM permission boundary ARN"
  type        = string
}

variable "runner_custom_policy_arns" {
  description = "Optional managed IAM policy ARNs to attach to the EC2 runner instance role. Use this when policy ARNs are computed by other resources."
  type        = list(string)
  default     = []
}

variable "enable_bedrock" {
  description = "Enable Amazon Bedrock access for EC2 runner instances"
  type        = bool
  default     = false
}

variable "enable_cache_isolation" {
  description = "Enable brokered, per-repository/per-branch credentials for Magic Cache data under scoped-cache/*. Direct S3 cache integrations always keep instance-profile access to the stack-shared cache/* namespace"
  type        = bool
  default     = false
}

variable "enable_stickydisk_isolation" {
  description = "Remove the legacy EBS volume/snapshot permissions from the runner instance role so all sticky-disk EBS operations happen exclusively on the control plane. Breaks the legacy v1 runs-on/snapshot action"
  type        = bool
  default     = false
}

variable "app_tag" {
  description = "Application version tag"
  type        = string
}

variable "bootstrap_tag" {
  description = "Bootstrap script version tag"
  type        = string
}

variable "ipv6_enabled" {
  description = "Enable IPv6 for runners"
  type        = bool
}

variable "runner_max_runtime" {
  description = "Maximum runtime in minutes for runners"
  type        = number
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
}

variable "stack_name" {
  description = "Example Fleet stack name."
  type        = string
  default     = "runs-on-fleet-example"
}

variable "aws_region" {
  description = "AWS region for the example."
  type        = string
  default     = "us-east-1"
}

variable "github_app_id" {
  description = "GitHub App ID for the example."
  type        = number
  default     = 123456
}

variable "github_app_private_key" {
  description = "GitHub App private key placeholder for the example."
  type        = string
  default     = <<-EOT
    -----BEGIN PRIVATE KEY-----
    example
    -----END PRIVATE KEY-----
  EOT
  sensitive   = true
}

variable "github_enterprise_pat" {
  description = "Optional enterprise PAT for enterprise-target mode."
  type        = string
  default     = null
  sensitive   = true
}

variable "github_base_url" {
  description = "GitHub host root URL for github.com or GHES."
  type        = string
  default     = "https://github.com"
}

variable "github_enterprise_name" {
  description = "Optional GitHub Enterprise slug for enterprise-target mode."
  type        = string
  default     = null
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com."
  type        = string
  default     = "runs-on-license-placeholder"
  sensitive   = true
}

variable "email" {
  description = "Email address for Fleet alerts."
  type        = string
  default     = "alerts@example.com"
}

variable "alert_slack_webhook_url" {
  description = "Optional Slack webhook URL for Fleet alerts."
  type        = string
  default     = ""
  sensitive   = true
}

variable "integration_step_security_api_key" {
  description = "Optional StepSecurity integration API key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "environment" {
  description = "Workflow targeting environment for the example."
  type        = string
  default     = "production"
}

variable "app_size" {
  description = "Example app-size preset for the Fleet worker."
  type        = string
  default     = "small"
}

variable "app_capacity_provider" {
  description = "Example Fleet worker capacity provider."
  type        = string
  default     = "fargate"
}

variable "vpc_id" {
  description = "Example VPC id."
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "public_subnet_ids" {
  description = "Example public subnet ids."
  type        = list(string)
  default     = ["subnet-0123456789abcdef0"]
}

variable "private_subnet_ids" {
  description = "Example private subnet ids."
  type        = list(string)
  default     = ["subnet-0fedcba9876543210"]
}

variable "images" {
  description = "Optional custom image catalog using fields supported by Fleet's ImageSpec. Built-in image names such as ubuntu24-full-x64 and ubuntu26-full-x64 do not need entries here."
  type        = map(any)
  default     = {}
}

variable "runners" {
  description = "Example runner catalog using fields supported by Fleet's RunnerSpec."
  type        = map(any)
  default = {
    small-x64 = {
      cpu    = 2
      ram    = 4
      family = ["c7"]
      image  = "ubuntu24-full-x64"
    }
    large-x64 = {
      cpu    = 4
      ram    = 8
      family = ["c7"]
      image  = "ubuntu24-full-x64"
    }
  }
}

variable "fleets" {
  description = "Example fleet catalog using the config module PoolSpec shape."
  type        = map(any)
  default = {
    linux-small = {
      timezone     = "UTC"
      runner_group = "platform"
      runner       = "small-x64"
    }
    linux-large = {
      timezone     = "UTC"
      runner_group = "platform"
      runner       = "large-x64"
    }
  }
}

variable "runtime_image" {
  description = "Example worker image."
  type        = string
  default     = "public.ecr.aws/c5h5o9k1/runs-on/runs-on:test"
}

variable "bootstrap_tag" {
  description = "Example bootstrap tag."
  type        = string
  default     = "v0.1.17"
}

variable "app_tag" {
  description = "Example app tag."
  type        = string
  default     = "dev"
}

variable "runner_max_runtime" {
  description = "Example max runtime in minutes."
  type        = number
  default     = 60
}

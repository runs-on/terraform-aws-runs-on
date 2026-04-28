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

variable "enterprise" {
  description = "Optional enterprise slug for enterprise-target mode."
  type        = string
  default     = null
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
  description = "Example image catalog using the config module ImageSpec shape."
  type        = map(any)
  default = {
    ubuntu24-full-x64 = {
      ami            = "ami-0123456789abcdef0"
      platform       = "linux"
      arch           = "x64"
      main_disk_size = 60
    }
  }
}

variable "runners" {
  description = "Example runner catalog using the config module RunnerSpec shape."
  type        = map(any)
  default = {
    small-x64 = {
      cpu    = 2
      ram    = 4
      family = ["c7"]
      image  = "ubuntu24-full-x64"
    }
  }
}

variable "pools" {
  description = "Example pool catalog using the config module PoolSpec shape."
  type        = map(any)
  default = {
    my-pool = {
      timezone     = "UTC"
      runner_group = "platform"
      runner       = "small-x64"
      schedule = [
        {
          name    = "default"
          hot     = 1
          stopped = 2
        }
      ]
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

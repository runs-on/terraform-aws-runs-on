# Note: This fixture requires mocked dependencies from storage, compute, and optional modules
# For actual testing, use the integration tests or Terragrunt scenarios

module "core" {
  source = "../../../modules/core"

  stack_name                         = var.stack_name
  github_organization                = var.github_organization
  license_key                        = var.license_key
  vpc_id                             = var.vpc_id
  public_subnet_ids                  = var.public_subnet_ids
  private_subnet_ids                 = var.private_subnet_ids
  security_group_ids                 = var.security_group_ids
  config_bucket_name                 = var.config_bucket_name
  cache_bucket_name                  = var.cache_bucket_name
  instance_profile_arn               = var.instance_profile_arn
  instance_role_name                 = var.instance_role_name
  launch_template_linux_default_id   = var.launch_template_linux_default_id
  launch_template_windows_default_id = var.launch_template_windows_default_id
  launch_template_linux_private_id   = var.launch_template_linux_private_id
  launch_template_windows_private_id = var.launch_template_windows_private_id
  app_cpu                            = var.app_cpu
  app_memory                         = var.app_memory
  environment                        = var.environment
}

variable "stack_name" {
  type = string
}

variable "github_organization" {
  type = string
}

variable "license_key" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type = list(string)
}

variable "config_bucket_name" {
  type = string
}

variable "cache_bucket_name" {
  type = string
}

variable "instance_profile_arn" {
  type = string
}

variable "instance_role_name" {
  type = string
}

variable "launch_template_linux_default_id" {
  type = string
}

variable "launch_template_windows_default_id" {
  type = string
}

variable "launch_template_linux_private_id" {
  type    = string
  default = ""
}

variable "launch_template_windows_private_id" {
  type    = string
  default = ""
}

variable "app_cpu" {
  type    = number
  default = 1024
}

variable "app_memory" {
  type    = number
  default = 2048
}

variable "environment" {
  type    = string
  default = "test"
}

output "app_runner_service_url" {
  value = module.core.app_runner_service_url
}

output "app_runner_service_arn" {
  value = module.core.app_runner_service_arn
}

output "main_queue_url" {
  value = module.core.main_queue_url
}

output "jobs_queue_url" {
  value = module.core.jobs_queue_url
}

output "locks_table_name" {
  value = module.core.locks_table_name
}

output "workflow_jobs_table_name" {
  value = module.core.workflow_jobs_table_name
}

output "alert_topic_arn" {
  value = module.core.alert_topic_arn
}

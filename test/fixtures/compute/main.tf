# Note: This fixture requires mocked dependencies from storage and optional modules
# For actual testing, use the integration tests or Terragrunt scenarios

module "compute" {
  source = "../../../modules/compute"

  stack_name              = var.stack_name
  vpc_id                  = var.vpc_id
  security_group_ids      = var.security_group_ids
  public_subnet_ids       = var.public_subnet_ids
  private_subnet_ids      = var.private_subnet_ids
  config_bucket_name      = var.config_bucket_name
  config_bucket_arn       = var.config_bucket_arn
  cache_bucket_name       = var.cache_bucket_name
  cache_bucket_arn        = var.cache_bucket_arn
  efs_id                  = var.efs_id
  ecr_repository_url      = var.ecr_repository_url
  log_retention_days      = var.log_retention_days
  permission_boundary_arn = var.permission_boundary_arn
  app_tag                 = var.app_tag
  bootstrap_tag           = var.bootstrap_tag
}

variable "stack_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type    = list(string)
  default = []
}

variable "config_bucket_name" {
  type = string
}

variable "config_bucket_arn" {
  type = string
}

variable "cache_bucket_name" {
  type = string
}

variable "cache_bucket_arn" {
  type = string
}

variable "efs_id" {
  type    = string
  default = ""
}

variable "ecr_repository_url" {
  type    = string
  default = ""
}

variable "log_retention_days" {
  type    = number
  default = 1
}

variable "permission_boundary_arn" {
  type    = string
  default = ""
}

variable "app_tag" {
  type    = string
  default = "v2.10.0"
}

variable "bootstrap_tag" {
  type    = string
  default = "v0.1.12"
}

output "instance_role_name" {
  value = module.compute.instance_role_name
}

output "instance_role_arn" {
  value = module.compute.instance_role_arn
}

output "instance_profile_arn" {
  value = module.compute.instance_profile_arn
}

output "launch_template_linux_default_id" {
  value = module.compute.launch_template_linux_default_id
}

output "launch_template_windows_default_id" {
  value = module.compute.launch_template_windows_default_id
}

output "launch_template_linux_private_id" {
  value = length(var.private_subnet_ids) > 0 ? module.compute.launch_template_linux_private_id : ""
}

output "launch_template_windows_private_id" {
  value = length(var.private_subnet_ids) > 0 ? module.compute.launch_template_windows_private_id : ""
}

output "log_group_name" {
  value = module.compute.log_group_name
}

# main.tf
# Root module for RunsOn infrastructure

# Storage module - S3 buckets for config, cache, and logging
module "storage" {
  source = "./modules/storage"

  stack_name            = var.stack_name
  cache_expiration_days = 30
  tags                  = var.tags
}

# Compute module - EC2 launch templates and IAM roles
module "compute" {
  source = "./modules/compute"

  stack_name         = var.stack_name
  security_group_ids = var.security_group_ids

  config_bucket_name = module.storage.config_bucket_name
  config_bucket_arn  = module.storage.config_bucket_arn
  cache_bucket_name  = module.storage.cache_bucket_name
  cache_bucket_arn   = module.storage.cache_bucket_arn

  private_networking_enabled = length(var.private_subnet_ids) > 0
  tags                       = var.tags
}

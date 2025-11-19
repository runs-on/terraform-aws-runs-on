# Outputs from the basic deployment

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "apprunner_service_url" {
  description = "App Runner service URL"
  value       = module.runs_on.apprunner_service_url
}

output "getting_started" {
  description = "Getting started instructions"
  value       = module.runs_on.getting_started
}

output "config_bucket_name" {
  description = "S3 bucket name for RunsOn configuration"
  value       = module.runs_on.config_bucket_name
}

output "cache_bucket_name" {
  description = "S3 bucket name for RunsOn cache"
  value       = module.runs_on.cache_bucket_name
}

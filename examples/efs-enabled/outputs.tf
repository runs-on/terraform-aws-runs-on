# Outputs from the EFS-enabled deployment

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "efs_file_system_id" {
  description = "EFS file system ID"
  value       = module.runs_on.efs_file_system_id
}

output "efs_file_system_dns_name" {
  description = "EFS file system DNS name"
  value       = module.runs_on.efs_file_system_dns_name
}

output "apprunner_service_url" {
  description = "App Runner service URL"
  value       = module.runs_on.apprunner_service_url
}

output "getting_started" {
  description = "Getting started instructions"
  value       = module.runs_on.getting_started
}

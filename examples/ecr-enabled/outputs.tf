# Outputs from the ECR-enabled deployment

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  description = "ECR repository URL for BuildKit cache"
  value       = module.runs_on.ecr_repository_url
}

output "apprunner_service_url" {
  description = "App Runner service URL"
  value       = module.runs_on.apprunner_service_url
}

output "getting_started" {
  description = "Getting started instructions"
  value       = module.runs_on.getting_started
}

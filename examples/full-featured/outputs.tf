# Outputs from the full-featured deployment

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

output "nat_gateway_ids" {
  description = "NAT Gateway IDs (for static egress IPs)"
  value       = module.vpc.natgw_ids
}

output "efs_file_system_id" {
  description = "EFS file system ID"
  value       = module.runs_on.efs_file_system_id
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

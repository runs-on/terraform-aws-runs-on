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

output "ingress_url" {
  description = "Public ingress URL"
  value       = module.runs_on.ingress.url
}

output "getting_started" {
  description = "Getting started instructions"
  value       = module.runs_on.stack.getting_started
}

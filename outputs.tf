# outputs.tf
# Root module outputs

output "config_bucket_name" {
  description = "S3 bucket name for configuration storage"
  value       = module.storage.config_bucket_name
}

output "cache_bucket_name" {
  description = "S3 bucket name for cache storage"
  value       = module.storage.cache_bucket_name
}

output "logging_bucket_name" {
  description = "S3 bucket name for access logs"
  value       = module.storage.logging_bucket_name
}

output "ec2_instance_role_name" {
  description = "Name of the EC2 instance IAM role"
  value       = module.compute.ec2_instance_role_name
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = module.compute.ec2_instance_profile_arn
}

output "launch_template_linux_default_id" {
  description = "ID of the Linux default launch template"
  value       = module.compute.launch_template_linux_default_id
}

output "launch_template_windows_default_id" {
  description = "ID of the Windows default launch template"
  value       = module.compute.launch_template_windows_default_id
}

output "log_group_name" {
  description = "CloudWatch log group name for EC2 instances"
  value       = module.compute.log_group_name
}

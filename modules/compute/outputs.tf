# modules/compute/outputs.tf
# Output values from the compute module

output "ec2_instance_role_arn" {
  description = "ARN of the EC2 instance IAM role"
  value       = aws_iam_role.ec2_instance.arn
}

output "ec2_instance_role_name" {
  description = "Name of the EC2 instance IAM role"
  value       = aws_iam_role.ec2_instance.name
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "launch_template_linux_default_id" {
  description = "ID of the Linux default launch template"
  value       = aws_launch_template.linux_default.id
}

output "launch_template_linux_default_latest_version" {
  description = "Latest version of the Linux default launch template"
  value       = aws_launch_template.linux_default.latest_version
}

output "launch_template_windows_default_id" {
  description = "ID of the Windows default launch template"
  value       = aws_launch_template.windows_default.id
}

output "launch_template_windows_default_latest_version" {
  description = "Latest version of the Windows default launch template"
  value       = aws_launch_template.windows_default.latest_version
}

output "launch_template_linux_private_id" {
  description = "ID of the Linux private launch template"
  value       = var.private_mode != "false" ? aws_launch_template.linux_private[0].id : null
}

output "launch_template_linux_private_latest_version" {
  description = "Latest version of the Linux private launch template"
  value       = var.private_mode != "false" ? aws_launch_template.linux_private[0].latest_version : null
}

output "launch_template_windows_private_id" {
  description = "ID of the Windows private launch template"
  value       = var.private_mode != "false" ? aws_launch_template.windows_private[0].id : null
}

output "launch_template_windows_private_latest_version" {
  description = "Latest version of the Windows private launch template"
  value       = var.private_mode != "false" ? aws_launch_template.windows_private[0].latest_version : null
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ec2_instances.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ec2_instances.arn
}

output "resource_group_name" {
  description = "Name of the EC2 resource group"
  value       = aws_resourcegroups_group.ec2_instances.name
}

output "resource_group_arn" {
  description = "ARN of the EC2 resource group"
  value       = aws_resourcegroups_group.ec2_instances.arn
}

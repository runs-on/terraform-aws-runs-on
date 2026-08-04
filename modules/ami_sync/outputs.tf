output "function_arn" {
  description = "ARN of the AMI sync Lambda function (null when disabled)."
  value       = var.enabled ? aws_lambda_function.ami_sync[0].arn : null
}

output "function_name" {
  description = "Name of the AMI sync Lambda function (null when disabled)."
  value       = var.enabled ? aws_lambda_function.ami_sync[0].function_name : null
}

output "role_arn" {
  description = "ARN of the Lambda execution role (null when disabled)."
  value       = var.enabled ? aws_iam_role.ami_sync[0].arn : null
}

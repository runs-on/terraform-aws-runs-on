# Root module outputs for RunsOn Flex

output "stack" {
  description = "RunsOn Flex stack metadata and operator-facing entrypoints"
  value = {
    name                          = var.stack_name
    aws_account_id                = local.account_id
    aws_region                    = local.region
    stack_config_secret_arn       = module.control_plane.config.stack_config_secret_arn
    license_status_parameter_name = module.control_plane.config.license_status_parameter
    dashboard                     = module.control_plane.dashboard
    waf                           = module.control_plane.waf
    getting_started = <<-EOT
      RunsOn Flex Infrastructure Deployed Successfully!

      Stack Name: ${var.stack_name}
      Region: ${local.region}
      Environment: ${var.environment}
${var.environment != "production" ? <<-WARNING

      WARNING: Non-production environment detected!
      Your GitHub workflows must include 'env=${var.environment}' in the runs-on label.
      Example: runs-on: runs-on=$family/env=${var.environment}
      See: https://runs-on.com/configuration/job-labels/#env
WARNING
  : ""}
      Get Started by clicking here -> ${module.control_plane.ingress.url}

      Read more on https://runs-on.com/docs or visit https://runs-on.com/guides/troubleshoot/ to fix common issues.
    EOT
}
}

output "platform" {
  description = "Shared runner platform resources for RunsOn Flex"
  value       = local.platform
}

output "runtime" {
  description = "RunsOn Flex runtime ECS resources"
  value       = module.control_plane.runtime
}

output "ingress" {
  description = "RunsOn Flex public ingress endpoints"
  value       = module.control_plane.ingress
}

output "queues" {
  description = "RunsOn Flex queue resources"
  value       = module.control_plane.queues
}

output "tables" {
  description = "RunsOn Flex DynamoDB tables"
  value       = module.control_plane.tables
}

output "alerts" {
  description = "RunsOn Flex alerting resources"
  value       = module.control_plane.alerts
}

output "optional_features" {
  description = "Optional Flex runner platform features"
  value       = local.platform.optional_features
}

output "stack" {
  description = "RunsOn Fleet stack metadata"
  value = {
    name           = var.stack_name
    aws_account_id = data.aws_caller_identity.current.account_id
    aws_region     = local.region
  }
}

output "platform" {
  description = "Shared runner platform resources for RunsOn Fleet"
  value       = local.platform
}

output "runtime" {
  description = "RunsOn Fleet runtime ECS resources"
  value       = module.control_plane.runtime
}

output "config" {
  description = "RunsOn Fleet runtime configuration secret"
  value       = module.control_plane.config
}

output "alerts" {
  description = "RunsOn Fleet alerting resources"
  value       = module.control_plane.alerts
}

output "workflow_contract" {
  description = "RunsOn Fleet workflow targeting contract"
  value       = module.control_plane.workflow_contract
}

output "dashboard" {
  description = "RunsOn Fleet CloudWatch dashboard"
  value       = module.control_plane.dashboard
}

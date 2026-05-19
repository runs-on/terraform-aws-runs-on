output "workflow_target_contract" {
  description = "Workflow targeting contract exposed by the example."
  value       = module.runs_on_fleet.workflow_contract.label
}

output "config_secret_arn" {
  description = "Rendered config secret ARN."
  value       = module.runs_on_fleet.config.secret_arn
}

output "runner_launch_template_ids" {
  description = "Launch template IDs keyed by runner name."
  value = {
    for name, template in module.runs_on_fleet.platform.launch_templates : name => template.id
  }
}

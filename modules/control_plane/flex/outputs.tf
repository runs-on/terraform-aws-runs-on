# Output values from the RunsOn Flex control plane module

output "config" {
  description = "Flex configuration secrets and parameters"
  value = {
    stack_config_secret_arn  = aws_secretsmanager_secret.runs_on_stack_config.arn
    license_status_parameter = aws_ssm_parameter.license_status.name
    github_apps_secret_arn   = aws_secretsmanager_secret.runs_on_github_apps.arn
  }
}

output "runtime" {
  description = "Flex runtime ECS resources"
  value = {
    service_arn         = module.runtime.runtime.service_arn
    service_name        = module.runtime.runtime.service_name
    cluster_name        = module.runtime.runtime.cluster_name
    cluster_arn         = module.runtime.runtime.cluster_arn
    log_group_name      = module.runtime.runtime.log_group_name
    task_definition_arn = module.runtime.runtime.task_definition_arn
    task_role_arn       = module.runtime.task_role.arn
    task_role_name      = module.runtime.task_role.name
  }
}

output "ingress" {
  description = "Flex public ingress endpoints"
  value = {
    url = local.public_ingress_base_url
  }
}

output "alerts" {
  description = "Flex alerting resources"
  value = {
    topic_arn                = aws_sns_topic.alerts.arn
    topic_name               = aws_sns_topic.alerts.name
    slack_webhook_lambda_arn = local.alerts.slack_webhook_url != "" ? aws_lambda_function.slack_webhook[0].arn : null
  }
}

output "queues" {
  description = "Flex queue resources"
  value = {
    webhooks = {
      url = aws_sqs_queue.webhooks.url
      arn = aws_sqs_queue.webhooks.arn
    }
    system = {
      url = aws_sqs_queue.system.url
      arn = aws_sqs_queue.system.arn
    }
    events = {
      url = aws_sqs_queue.events.url
      arn = aws_sqs_queue.events.arn
    }
  }
}

output "tables" {
  description = "Flex DynamoDB tables"
  value = {
    locks = {
      name = aws_dynamodb_table.locks.name
      arn  = aws_dynamodb_table.locks.arn
    }
    workflow_jobs = {
      name = aws_dynamodb_table.workflow_jobs.name
      arn  = aws_dynamodb_table.workflow_jobs.arn
    }
  }
}

output "dashboard" {
  description = "Flex dashboard resources"
  value = {
    url  = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.stack_name}-Dashboard"
    name = aws_cloudwatch_dashboard.runs_on.dashboard_name
  }
}

output "waf" {
  description = "Flex WAF resources"
  value = {
    web_acl_arn = local.operations.enable_waf ? local.effective_public_ingress_web_acl_arn : null
    web_acl_id = local.effective_public_ingress_web_acl_arn != null ? (
      local.using_user_managed_public_ingress_waf
      ? element(split("/", local.public_ingress_web_acl_arn_trimmed), length(split("/", local.public_ingress_web_acl_arn_trimmed)) - 1)
      : aws_wafv2_web_acl.this[0].id
    ) : null
  }
}

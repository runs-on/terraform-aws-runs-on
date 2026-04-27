# Flex Control Plane Module

Provisions the RunsOn Flex control plane for Terraform-based deployments.

## Runtime Shape

The Flex control plane module deploys:

- an ECS worker service that runs the RunsOn Flex server
- an API Gateway plus Lambda public ingress for setup, health checks, and webhooks
- SQS queues for webhook, system, and event processing
- DynamoDB tables for locks and workflow jobs
- SNS, EventBridge, and CloudWatch resources for alerting and operations
- Secrets Manager secrets for stack config and GitHub App config

## Discovery Contract

`runs-on-stack-name` is the only supported discovery tag. Tooling should discover the stack config secret first, then use the secret contents plus live AWS reads for runtime inspection.

The stack config secret is pinned into the worker task definition via:

- `RUNS_ON_STACK_CONFIG_SECRET_ARN`
- `RUNS_ON_STACK_CONFIG_SECRET_VERSION`

That pinned secret contains both runtime config and CLI-facing metadata, including:

- `IngressURL`
- `ServiceLogGroupName`
- `Ec2InstanceLogGroupArn`

## Important Outputs

- `config`
- `runtime`
- `ingress`
- `queues`
- `tables`
- `alerts`
- `dashboard`
- `waf`

## Notes

The Flex control plane writes `app_size` into stack config, then resolves that preset into ECS CPU, ECS memory, webhook worker concurrency, provisioning worker concurrency, registration worker concurrency, and the launch-related EC2 limiter assumptions the server applies at runtime.

When `ebs_encryption_key_id` points at a customer-managed KMS key, prefer a full key ARN, especially for cross-account keys. The generated worker task role `arn:aws:iam::<account-id>:role/<stack-name>-service-role` must be allowed to use that key. The module adds the IAM permissions on its side, but external or cross-account key policies still have to trust that role manually.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | >= 2.0 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.21.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_runtime"></a> [runtime](#module\_runtime) | ../runtime | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_api_gateway_deployment.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment) | resource |
| [aws_api_gateway_integration.github_webhooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_integration.readyz](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_integration.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_integration.setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_integration.setup_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_method.github_webhooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method.readyz](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method.setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method.setup_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method) | resource |
| [aws_api_gateway_method_settings.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method_settings) | resource |
| [aws_api_gateway_resource.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource) | resource |
| [aws_api_gateway_resource.github_webhooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource) | resource |
| [aws_api_gateway_resource.readyz](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource) | resource |
| [aws_api_gateway_resource.setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource) | resource |
| [aws_api_gateway_resource.setup_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource) | resource |
| [aws_api_gateway_rest_api.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api) | resource |
| [aws_api_gateway_stage.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage) | resource |
| [aws_budgets_budget.app_daily_budget](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_cloudwatch_dashboard.runs_on](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_event_rule.github_waf_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_rule.spot_interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.github_waf_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.spot_interruption_to_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.github_apps_setup_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.github_runner_cache_refresh_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.github_waf_sync_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.public_ingress_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.stack_config_materializer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_dynamodb_table.locks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table.workflow_jobs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.github_apps_setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.github_runner_cache_refresh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.github_waf_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.stack_config_materializer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.github_apps_setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.github_runner_cache_refresh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.github_waf_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.stack_config_materializer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.github_apps_setup_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.github_runner_cache_refresh_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.github_waf_sync_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.public_ingress_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.slack_webhook_basic_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.github_apps_setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.github_runner_cache_refresh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.github_waf_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.stack_config_materializer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_invocation.github_waf_sync_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_invocation) | resource |
| [aws_lambda_invocation.stack_config_materializer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_invocation) | resource |
| [aws_lambda_permission.github_apps_setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_lambda_permission.github_waf_sync_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_lambda_permission.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_lambda_permission.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_scheduler_schedule.cost_allocation_tag](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule.cost_report](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule.github_runner_cache_refresh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_secretsmanager_secret.runs_on_github_apps](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.runs_on_stack_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.runs_on_github_apps](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_sns_topic.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sns_topic_subscription.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sqs_queue.events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.system](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.system_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.webhooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.webhooks_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.events_eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_sqs_queue_policy.webhooks_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_ssm_parameter.license_status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.otel_exporter_headers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_wafv2_ip_set.allowed_ips_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set) | resource |
| [aws_wafv2_ip_set.allowed_ips_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set) | resource |
| [aws_wafv2_web_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_association.public_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [archive_file.github_apps_setup](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.github_runner_cache_refresh](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.github_waf_sync](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.public_ingress](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.slack_webhook](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.stack_config_materializer](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID | `string` | n/a | yes |
| <a name="input_alerts"></a> [alerts](#input\_alerts) | Flex alert delivery settings | <pre>object({<br/>    email             = string<br/>    slack_webhook_url = string<br/>  })</pre> | n/a | yes |
| <a name="input_compute"></a> [compute](#input\_compute) | Shared runner compute resources | <pre>object({<br/>    runner_iam = object({<br/>      role_arn     = string<br/>      role_name    = string<br/>      role_id      = string<br/>      profile_arn  = string<br/>      profile_name = string<br/>    })<br/>    runner_logs = object({<br/>      group_name          = string<br/>      group_arn           = string<br/>      resource_group_name = string<br/>      resource_group_arn  = string<br/>    })<br/>    launch_templates = object({<br/>      linux_default = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      linux_default_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_default = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_default_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      linux_private = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      linux_private_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_private = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_private_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Tag key for cost allocation | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_extras"></a> [extras](#input\_extras) | Shared runner extras resources | <pre>object({<br/>    cache = object({<br/>      bucket_id   = string<br/>      bucket_name = string<br/>      bucket_arn  = string<br/>    })<br/>    efs = object({<br/>      enabled           = bool<br/>      file_system_id    = string<br/>      file_system_arn   = string<br/>      file_system_dns   = string<br/>      security_group_id = string<br/>    })<br/>    ecr = object({<br/>      enabled         = bool<br/>      repository_arn  = string<br/>      repository_name = string<br/>      repository_url  = string<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_github"></a> [github](#input\_github) | GitHub settings and optional declarative app secret payload | <pre>object({<br/>    organization   = string<br/>    enterprise_url = string<br/>    api_strategy   = string<br/>    apps           = any<br/>  })</pre> | n/a | yes |
| <a name="input_license_key"></a> [license\_key](#input\_license\_key) | RunsOn license key | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Shared runner networking resources | <pre>object({<br/>    vpc_id             = string<br/>    private_mode       = string<br/>    public_subnet_ids  = list(string)<br/>    private_subnet_ids = list(string)<br/>    security_group_ids = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_operations"></a> [operations](#input\_operations) | Flex operational controls and integrations | <pre>object({<br/>    app_budget_daily_usd              = number<br/>    enable_cost_reports               = bool<br/>    spot_circuit_breaker              = string<br/>    integration_step_security_api_key = string<br/>    enable_admin_routes               = bool<br/>    enable_waf                        = bool<br/>    public_ingress_web_acl_arn        = string<br/>  })</pre> | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | n/a | yes |
| <a name="input_runner"></a> [runner](#input\_runner) | Flex EC2 runner settings published into stack config | <pre>object({<br/>    ssh_allowed              = bool<br/>    ebs_encryption_key_id    = string<br/>    max_runtime              = number<br/>    config_auto_extends_from = string<br/>    custom_tags              = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_runtime"></a> [runtime](#input\_runtime) | Flex runtime settings | <pre>object({<br/>    image                     = string<br/>    tag                       = string<br/>    maintenance_mode          = bool<br/>    size                      = string<br/>    private_mode              = string<br/>    ecr_repository_url        = string<br/>    custom_policy_arn         = string<br/>    otel_exporter_endpoint    = string<br/>    otel_exporter_headers     = string<br/>    otel_exporter_temporality = string<br/>    otel_logs_enabled         = bool<br/>    otel_traces_enabled       = bool<br/>    logger_level              = string<br/>    extra_env_vars            = map(string)<br/>  })</pre> | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Stack name for resource naming | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alerts"></a> [alerts](#output\_alerts) | Flex alerting resources |
| <a name="output_config"></a> [config](#output\_config) | Flex configuration secrets and parameters |
| <a name="output_dashboard"></a> [dashboard](#output\_dashboard) | Flex dashboard resources |
| <a name="output_ingress"></a> [ingress](#output\_ingress) | Flex public ingress endpoints |
| <a name="output_queues"></a> [queues](#output\_queues) | Flex queue resources |
| <a name="output_runtime"></a> [runtime](#output\_runtime) | Flex runtime ECS resources |
| <a name="output_tables"></a> [tables](#output\_tables) | Flex DynamoDB tables |
| <a name="output_waf"></a> [waf](#output\_waf) | Flex WAF resources |
<!-- END_TF_DOCS -->

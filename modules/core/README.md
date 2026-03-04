# Core Module

App Runner service, queues, and state management for RunsOn.

## What's Included

- **App Runner** - Runs the RunsOn orchestrator
- **SQS queues** - Job processing, GitHub events, termination handling
- **DynamoDB tables** - Distributed locking and job tracking
- **SNS topic** - Alerts and notifications
- **EventBridge rules** - Spot interruption handling, cost reports

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | n/a |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.21.0 |
| <a name="provider_http"></a> [http](#provider\_http) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_apprunner_auto_scaling_configuration_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apprunner_auto_scaling_configuration_version) | resource |
| [aws_apprunner_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apprunner_service) | resource |
| [aws_apprunner_vpc_connector.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apprunner_vpc_connector) | resource |
| [aws_cloudwatch_dashboard.runs_on](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_event_rule.spot_interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.spot_interruption_to_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_metric_alarm.app_daily_budget](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.sqs_main_oldest_message](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_dynamodb_table.locks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table.workflow_jobs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.apprunner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.apprunner_ecr_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.apprunner_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.apprunner_ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.apprunner_ecr_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.slack_webhook_basic_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_scheduler_schedule.cost_allocation_tag](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule.cost_report](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_sns_topic.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sns_topic_subscription.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sns_topic_subscription.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sqs_queue.events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.github_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.housekeeping](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.jobs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.jobs_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.main_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.pool](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.pool_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.termination](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.events_eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_sqs_queue_policy.main_dead_letter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_ssm_parameter.integration_step_security_api_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.license_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.otel_exporter_headers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.server_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_wafv2_ip_set.allowed_ips_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set) | resource |
| [aws_wafv2_ip_set.allowed_ips_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set) | resource |
| [aws_wafv2_web_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_association.apprunner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID | `string` | n/a | yes |
| <a name="input_alert_https_endpoint"></a> [alert\_https\_endpoint](#input\_alert\_https\_endpoint) | HTTPS endpoint for alerts | `string` | n/a | yes |
| <a name="input_alert_slack_webhook_url"></a> [alert\_slack\_webhook\_url](#input\_alert\_slack\_webhook\_url) | Slack webhook URL for alerts | `string` | n/a | yes |
| <a name="input_app_alarm_daily_minutes"></a> [app\_alarm\_daily\_minutes](#input\_app\_alarm\_daily\_minutes) | Daily budget in minutes for the App Runner service | `number` | n/a | yes |
| <a name="input_app_cpu"></a> [app\_cpu](#input\_app\_cpu) | CPU units for App Runner service | `number` | n/a | yes |
| <a name="input_app_debug"></a> [app\_debug](#input\_app\_debug) | Enable debug mode for RunsOn stack | `bool` | n/a | yes |
| <a name="input_app_image"></a> [app\_image](#input\_app\_image) | App Runner image identifier | `string` | n/a | yes |
| <a name="input_app_memory"></a> [app\_memory](#input\_app\_memory) | Memory in MB for App Runner service | `number` | n/a | yes |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application version tag | `string` | n/a | yes |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap script version tag | `string` | n/a | yes |
| <a name="input_cache_bucket_arn"></a> [cache\_bucket\_arn](#input\_cache\_bucket\_arn) | S3 bucket ARN for cache | `string` | n/a | yes |
| <a name="input_cache_bucket_name"></a> [cache\_bucket\_name](#input\_cache\_bucket\_name) | S3 bucket name for cache | `string` | n/a | yes |
| <a name="input_config_bucket_arn"></a> [config\_bucket\_arn](#input\_config\_bucket\_arn) | S3 bucket ARN for configuration | `string` | n/a | yes |
| <a name="input_config_bucket_name"></a> [config\_bucket\_name](#input\_config\_bucket\_name) | S3 bucket name for configuration | `string` | n/a | yes |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Tag key for cost allocation | `string` | n/a | yes |
| <a name="input_default_admins"></a> [default\_admins](#input\_default\_admins) | Comma-separated list of default admin usernames | `string` | n/a | yes |
| <a name="input_ebs_encryption_key_id"></a> [ebs\_encryption\_key\_id](#input\_ebs\_encryption\_key\_id) | KMS key ID for EBS encryption (leave empty for AWS managed key) | `string` | n/a | yes |
| <a name="input_ec2_instance_profile_arn"></a> [ec2\_instance\_profile\_arn](#input\_ec2\_instance\_profile\_arn) | ARN of the EC2 instance profile | `string` | n/a | yes |
| <a name="input_ec2_instance_role_arn"></a> [ec2\_instance\_role\_arn](#input\_ec2\_instance\_role\_arn) | ARN of the EC2 instance IAM role | `string` | n/a | yes |
| <a name="input_ec2_instance_role_name"></a> [ec2\_instance\_role\_name](#input\_ec2\_instance\_role\_name) | Name of the EC2 instance IAM role | `string` | n/a | yes |
| <a name="input_ec2_queue_size"></a> [ec2\_queue\_size](#input\_ec2\_queue\_size) | EC2 queue size | `number` | n/a | yes |
| <a name="input_email"></a> [email](#input\_email) | Email address for alerts | `string` | n/a | yes |
| <a name="input_enable_cost_reports"></a> [enable\_cost\_reports](#input\_enable\_cost\_reports) | Enable automated cost reports | `bool` | n/a | yes |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Create a CloudWatch dashboard for monitoring RunsOn operations | `bool` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., prod, dev, staging) | `string` | n/a | yes |
| <a name="input_github_api_strategy"></a> [github\_api\_strategy](#input\_github\_api\_strategy) | Strategy for GitHub API calls (normal, conservative) | `string` | n/a | yes |
| <a name="input_github_enterprise_url"></a> [github\_enterprise\_url](#input\_github\_enterprise\_url) | GitHub Enterprise URL (optional) | `string` | n/a | yes |
| <a name="input_github_organization"></a> [github\_organization](#input\_github\_organization) | GitHub organization or username | `string` | n/a | yes |
| <a name="input_integration_step_security_api_key"></a> [integration\_step\_security\_api\_key](#input\_integration\_step\_security\_api\_key) | StepSecurity integration API key | `string` | n/a | yes |
| <a name="input_launch_template_linux_default_id"></a> [launch\_template\_linux\_default\_id](#input\_launch\_template\_linux\_default\_id) | ID of the Linux default launch template | `string` | n/a | yes |
| <a name="input_launch_template_linux_private_id"></a> [launch\_template\_linux\_private\_id](#input\_launch\_template\_linux\_private\_id) | ID of the Linux private launch template | `string` | n/a | yes |
| <a name="input_launch_template_windows_default_id"></a> [launch\_template\_windows\_default\_id](#input\_launch\_template\_windows\_default\_id) | ID of the Windows default launch template | `string` | n/a | yes |
| <a name="input_launch_template_windows_private_id"></a> [launch\_template\_windows\_private\_id](#input\_launch\_template\_windows\_private\_id) | ID of the Windows private launch template | `string` | n/a | yes |
| <a name="input_license_key"></a> [license\_key](#input\_license\_key) | RunsOn license key obtained from runs-on.com | `string` | n/a | yes |
| <a name="input_logger_level"></a> [logger\_level](#input\_logger\_level) | Log level: debug, info, warn, or error | `string` | n/a | yes |
| <a name="input_otel_exporter_endpoint"></a> [otel\_exporter\_endpoint](#input\_otel\_exporter\_endpoint) | OpenTelemetry exporter endpoint | `string` | n/a | yes |
| <a name="input_otel_exporter_headers"></a> [otel\_exporter\_headers](#input\_otel\_exporter\_headers) | OpenTelemetry exporter headers | `string` | n/a | yes |
| <a name="input_private_mode"></a> [private\_mode](#input\_private\_mode) | Private networking mode: 'false', 'true', 'always', or 'only' | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet IDs | `list(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | n/a | yes |
| <a name="input_runner_config_auto_extends_from"></a> [runner\_config\_auto\_extends\_from](#input\_runner\_config\_auto\_extends\_from) | Repository to auto-extend runner config from (e.g., '.github-private') | `string` | n/a | yes |
| <a name="input_runner_custom_tags"></a> [runner\_custom\_tags](#input\_runner\_custom\_tags) | Custom tags for runners | `list(string)` | n/a | yes |
| <a name="input_runner_default_disk_size"></a> [runner\_default\_disk\_size](#input\_runner\_default\_disk\_size) | Default EBS volume size in GB | `number` | n/a | yes |
| <a name="input_runner_default_volume_throughput"></a> [runner\_default\_volume\_throughput](#input\_runner\_default\_volume\_throughput) | Default EBS volume throughput in MiB/s | `number` | n/a | yes |
| <a name="input_runner_large_disk_size"></a> [runner\_large\_disk\_size](#input\_runner\_large\_disk\_size) | Large EBS volume size in GB | `number` | n/a | yes |
| <a name="input_runner_large_volume_throughput"></a> [runner\_large\_volume\_throughput](#input\_runner\_large\_volume\_throughput) | Large EBS volume throughput in MiB/s | `number` | n/a | yes |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes for runners | `number` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs for App Runner | `list(string)` | n/a | yes |
| <a name="input_server_password"></a> [server\_password](#input\_server\_password) | Password for RunsOn server admin interface | `string` | n/a | yes |
| <a name="input_spot_circuit_breaker"></a> [spot\_circuit\_breaker](#input\_spot\_circuit\_breaker) | Spot circuit breaker config (e.g., '2/15/30' = 2 failures in 15min, block for 30min) | `string` | n/a | yes |
| <a name="input_sqs_queue_oldest_message_threshold_seconds"></a> [sqs\_queue\_oldest\_message\_threshold\_seconds](#input\_sqs\_queue\_oldest\_message\_threshold\_seconds) | Threshold in seconds for oldest message in SQS queues | `number` | n/a | yes |
| <a name="input_ssh_allowed"></a> [ssh\_allowed](#input\_ssh\_allowed) | Allow SSH access to runners | `bool` | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Stack name for resource naming | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where RunsOn is deployed | `string` | n/a | yes |
| <a name="input_app_ecr_repository_url"></a> [app\_ecr\_repository\_url](#input\_app\_ecr\_repository\_url) | Private ECR repository URL for RunsOn image. When specified, App Runner will pull from this private ECR instead of public ECR. | `string` | `""` | no |
| <a name="input_enable_waf"></a> [enable\_waf](#input\_enable\_waf) | Enable AWS WAF for App Runner service | `bool` | `false` | no |
| <a name="input_waf_allowed_ipv4_cidrs"></a> [waf\_allowed\_ipv4\_cidrs](#input\_waf\_allowed\_ipv4\_cidrs) | List of IPv4 CIDR blocks to allow through WAF (in addition to GitHub webhook IPs) | `list(string)` | `[]` | no |
| <a name="input_waf_allowed_ipv6_cidrs"></a> [waf\_allowed\_ipv6\_cidrs](#input\_waf\_allowed\_ipv6\_cidrs) | List of IPv6 CIDR blocks to allow through WAF (in addition to GitHub webhook IPs) | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_alarm_arn"></a> [app\_alarm\_arn](#output\_app\_alarm\_arn) | ARN of the App Runner daily budget alarm |
| <a name="output_apprunner_log_group_name"></a> [apprunner\_log\_group\_name](#output\_apprunner\_log\_group\_name) | CloudWatch log group name for App Runner service |
| <a name="output_apprunner_service_arn"></a> [apprunner\_service\_arn](#output\_apprunner\_service\_arn) | ARN of the App Runner service |
| <a name="output_apprunner_service_id"></a> [apprunner\_service\_id](#output\_apprunner\_service\_id) | ID of the App Runner service |
| <a name="output_apprunner_service_status"></a> [apprunner\_service\_status](#output\_apprunner\_service\_status) | Status of the App Runner service |
| <a name="output_apprunner_service_url"></a> [apprunner\_service\_url](#output\_apprunner\_service\_url) | URL of the App Runner service |
| <a name="output_dashboard_name"></a> [dashboard\_name](#output\_dashboard\_name) | Name of the CloudWatch Dashboard |
| <a name="output_dashboard_url"></a> [dashboard\_url](#output\_dashboard\_url) | URL to the CloudWatch Dashboard |
| <a name="output_dynamodb_locks_table_arn"></a> [dynamodb\_locks\_table\_arn](#output\_dynamodb\_locks\_table\_arn) | ARN of the DynamoDB locks table |
| <a name="output_dynamodb_locks_table_name"></a> [dynamodb\_locks\_table\_name](#output\_dynamodb\_locks\_table\_name) | Name of the DynamoDB locks table |
| <a name="output_dynamodb_workflow_jobs_table_arn"></a> [dynamodb\_workflow\_jobs\_table\_arn](#output\_dynamodb\_workflow\_jobs\_table\_arn) | ARN of the DynamoDB workflow jobs table |
| <a name="output_dynamodb_workflow_jobs_table_name"></a> [dynamodb\_workflow\_jobs\_table\_name](#output\_dynamodb\_workflow\_jobs\_table\_name) | Name of the DynamoDB workflow jobs table |
| <a name="output_eventbridge_spot_interruption_rule_arn"></a> [eventbridge\_spot\_interruption\_rule\_arn](#output\_eventbridge\_spot\_interruption\_rule\_arn) | ARN of the EventBridge spot interruption rule |
| <a name="output_slack_webhook_lambda_arn"></a> [slack\_webhook\_lambda\_arn](#output\_slack\_webhook\_lambda\_arn) | ARN of the Slack webhook Lambda function |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS alerts topic |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | Name of the SNS alerts topic |
| <a name="output_sqs_alarm_main_arn"></a> [sqs\_alarm\_main\_arn](#output\_sqs\_alarm\_main\_arn) | ARN of the SQS Main Queue oldest message alarm |
| <a name="output_sqs_queue_events_url"></a> [sqs\_queue\_events\_url](#output\_sqs\_queue\_events\_url) | URL of the events SQS queue |
| <a name="output_sqs_queue_github_url"></a> [sqs\_queue\_github\_url](#output\_sqs\_queue\_github\_url) | URL of the github SQS queue |
| <a name="output_sqs_queue_housekeeping_url"></a> [sqs\_queue\_housekeeping\_url](#output\_sqs\_queue\_housekeeping\_url) | URL of the housekeeping SQS queue |
| <a name="output_sqs_queue_jobs_url"></a> [sqs\_queue\_jobs\_url](#output\_sqs\_queue\_jobs\_url) | URL of the jobs SQS queue |
| <a name="output_sqs_queue_main_arn"></a> [sqs\_queue\_main\_arn](#output\_sqs\_queue\_main\_arn) | ARN of the main SQS queue |
| <a name="output_sqs_queue_main_url"></a> [sqs\_queue\_main\_url](#output\_sqs\_queue\_main\_url) | URL of the main SQS queue |
| <a name="output_sqs_queue_pool_url"></a> [sqs\_queue\_pool\_url](#output\_sqs\_queue\_pool\_url) | URL of the pool SQS queue |
| <a name="output_sqs_queue_termination_url"></a> [sqs\_queue\_termination\_url](#output\_sqs\_queue\_termination\_url) | URL of the termination SQS queue |
| <a name="output_waf_web_acl_arn"></a> [waf\_web\_acl\_arn](#output\_waf\_web\_acl\_arn) | ARN of the WAF Web ACL |
| <a name="output_waf_web_acl_id"></a> [waf\_web\_acl\_id](#output\_waf\_web\_acl\_id) | ID of the WAF Web ACL |
<!-- END_TF_DOCS -->

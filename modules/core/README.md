# Core Module

Core orchestration module for RunsOn - manages App Runner service, SQS queues, DynamoDB tables, SNS topics, and EventBridge rules.

## Features

- App Runner service for RunsOn orchestration
- SQS queues for job processing (7 queues)
- DynamoDB tables for locks and workflow job tracking
- SNS topic for alerts and notifications
- EventBridge rules for Spot interruption handling
- Scheduler for automated cost reports
- VPC connector for private networking (optional)
- Slack/Email/HTTPS alert subscriptions (optional)

## Usage

```hcl
module "core" {
  source = "./modules/core"

  stack_name         = "runs-on-prod"
  environment        = "production"
  
  github_organization = "my-org"
  license_key        = var.license_key

  # Networking
  vpc_id             = "vpc-123"
  public_subnet_ids  = ["subnet-abc", "subnet-def"]
  security_group_ids = ["sg-123"]

  # From storage module
  config_bucket_name = module.storage.config_bucket_name
  config_bucket_arn  = module.storage.config_bucket_arn
  cache_bucket_name  = module.storage.cache_bucket_name
  cache_bucket_arn   = module.storage.cache_bucket_arn

  # From compute module
  ec2_instance_role_name           = module.compute.ec2_instance_role_name
  ec2_instance_role_arn            = module.compute.ec2_instance_role_arn
  ec2_instance_profile_arn         = module.compute.ec2_instance_profile_arn
  launch_template_linux_default_id = module.compute.launch_template_linux_default_id
  launch_template_windows_default_id = module.compute.launch_template_windows_default_id

  # Optional: Alerts
  alert_email = "devops@company.com"
}
```

## Components

### App Runner Service
- Orchestrates GitHub Actions runner provisioning
- Processes queue messages
- Manages runner lifecycle
- Auto-scaling configuration

### SQS Queues (7 total)
- **Main Queue**: Primary job processing (FIFO)
- **Jobs Queue**: Workflow job scheduling (FIFO)
- **GitHub Queue**: GitHub registration tasks (FIFO)
- **Pool Queue**: Pool management
- **Housekeeping Queue**: Maintenance tasks
- **Termination Queue**: Runner termination
- **Events Queue**: AWS events (Spot interruptions, scheduled tasks)

### DynamoDB Tables
- **Locks Table**: Distributed locking
- **Workflow Jobs Table**: Job tracking with GSI for queries

### SNS Topics
- **Alerts Topic**: Notifications for errors, warnings, cost reports

### EventBridge Rules
- **Spot Interruption**: Captures EC2 Spot warnings
- **Cost Reports**: Scheduled daily reports (optional)

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.21.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_apprunner_auto_scaling_configuration_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apprunner_auto_scaling_configuration_version) | resource |
| [aws_apprunner_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apprunner_service) | resource |
| [aws_apprunner_vpc_connector.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apprunner_vpc_connector) | resource |
| [aws_cloudwatch_event_rule.spot_interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.spot_interruption_to_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_dynamodb_table.locks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table.workflow_jobs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.apprunner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.apprunner_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.apprunner_ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_scheduler_schedule.cost_allocation_tag](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule.cost_report](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_sns_topic.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sns_topic_subscription.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
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

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cache_bucket_arn"></a> [cache\_bucket\_arn](#input\_cache\_bucket\_arn) | S3 bucket ARN for cache | `string` | n/a | yes |
| <a name="input_cache_bucket_name"></a> [cache\_bucket\_name](#input\_cache\_bucket\_name) | S3 bucket name for cache | `string` | n/a | yes |
| <a name="input_config_bucket_arn"></a> [config\_bucket\_arn](#input\_config\_bucket\_arn) | S3 bucket ARN for configuration | `string` | n/a | yes |
| <a name="input_config_bucket_name"></a> [config\_bucket\_name](#input\_config\_bucket\_name) | S3 bucket name for configuration | `string` | n/a | yes |
| <a name="input_ec2_instance_profile_arn"></a> [ec2\_instance\_profile\_arn](#input\_ec2\_instance\_profile\_arn) | ARN of the EC2 instance profile | `string` | n/a | yes |
| <a name="input_ec2_instance_role_arn"></a> [ec2\_instance\_role\_arn](#input\_ec2\_instance\_role\_arn) | ARN of the EC2 instance IAM role | `string` | n/a | yes |
| <a name="input_ec2_instance_role_name"></a> [ec2\_instance\_role\_name](#input\_ec2\_instance\_role\_name) | Name of the EC2 instance IAM role | `string` | n/a | yes |
| <a name="input_github_organization"></a> [github\_organization](#input\_github\_organization) | GitHub organization or username | `string` | n/a | yes |
| <a name="input_launch_template_linux_default_id"></a> [launch\_template\_linux\_default\_id](#input\_launch\_template\_linux\_default\_id) | ID of the Linux default launch template | `string` | n/a | yes |
| <a name="input_launch_template_windows_default_id"></a> [launch\_template\_windows\_default\_id](#input\_launch\_template\_windows\_default\_id) | ID of the Windows default launch template | `string` | n/a | yes |
| <a name="input_license_key"></a> [license\_key](#input\_license\_key) | RunsOn license key | `string` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet IDs | `list(string)` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs for App Runner | `list(string)` | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Stack name for resource naming | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where RunsOn is deployed | `string` | n/a | yes |
| <a name="input_alert_https_endpoint"></a> [alert\_https\_endpoint](#input\_alert\_https\_endpoint) | HTTPS endpoint for alerts | `string` | `""` | no |
| <a name="input_alert_slack_webhook_url"></a> [alert\_slack\_webhook\_url](#input\_alert\_slack\_webhook\_url) | Slack webhook URL for alerts | `string` | `""` | no |
| <a name="input_app_cpu"></a> [app\_cpu](#input\_app\_cpu) | CPU units for App Runner service | `number` | `1024` | no |
| <a name="input_app_image"></a> [app\_image](#input\_app\_image) | App Runner image identifier | `string` | `"public.ecr.aws/c5h5o9k1/runs-on/runs-on:v2.10.0"` | no |
| <a name="input_app_memory"></a> [app\_memory](#input\_app\_memory) | Memory in MB for App Runner service | `number` | `2048` | no |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application version tag | `string` | `"v2.10.0"` | no |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap script version tag | `string` | `"v0.1.12"` | no |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Tag key for cost allocation | `string` | `"CostCenter"` | no |
| <a name="input_default_admins"></a> [default\_admins](#input\_default\_admins) | Default admins | `string` | `""` | no |
| <a name="input_ebs_encryption_key_id"></a> [ebs\_encryption\_key\_id](#input\_ebs\_encryption\_key\_id) | KMS key ID for EBS encryption | `string` | `""` | no |
| <a name="input_ec2_queue_size"></a> [ec2\_queue\_size](#input\_ec2\_queue\_size) | EC2 queue size | `number` | `50` | no |
| <a name="input_email"></a> [email](#input\_email) | Email address for alerts | `string` | `""` | no |
| <a name="input_enable_cost_reports"></a> [enable\_cost\_reports](#input\_enable\_cost\_reports) | Enable automated cost reports | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., prod, dev, staging) | `string` | `"production"` | no |
| <a name="input_github_api_strategy"></a> [github\_api\_strategy](#input\_github\_api\_strategy) | GitHub API strategy | `string` | `"default"` | no |
| <a name="input_github_enterprise_url"></a> [github\_enterprise\_url](#input\_github\_enterprise\_url) | GitHub Enterprise URL (optional) | `string` | `""` | no |
| <a name="input_integration_step_security_api_key"></a> [integration\_step\_security\_api\_key](#input\_integration\_step\_security\_api\_key) | StepSecurity integration API key | `string` | `""` | no |
| <a name="input_launch_template_linux_private_id"></a> [launch\_template\_linux\_private\_id](#input\_launch\_template\_linux\_private\_id) | ID of the Linux private launch template | `string` | `null` | no |
| <a name="input_launch_template_windows_private_id"></a> [launch\_template\_windows\_private\_id](#input\_launch\_template\_windows\_private\_id) | ID of the Windows private launch template | `string` | `null` | no |
| <a name="input_logger_level"></a> [logger\_level](#input\_logger\_level) | Logger level | `string` | `"info"` | no |
| <a name="input_otel_exporter_endpoint"></a> [otel\_exporter\_endpoint](#input\_otel\_exporter\_endpoint) | OpenTelemetry exporter endpoint | `string` | `""` | no |
| <a name="input_otel_exporter_headers"></a> [otel\_exporter\_headers](#input\_otel\_exporter\_headers) | OpenTelemetry exporter headers | `string` | `""` | no |
| <a name="input_private_networking_enabled"></a> [private\_networking\_enabled](#input\_private\_networking\_enabled) | Enable private networking for App Runner | `bool` | `false` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs | `list(string)` | `[]` | no |
| <a name="input_runner_config_auto_extends_from"></a> [runner\_config\_auto\_extends\_from](#input\_runner\_config\_auto\_extends\_from) | Runner config auto extends from | `string` | `""` | no |
| <a name="input_runner_custom_tags"></a> [runner\_custom\_tags](#input\_runner\_custom\_tags) | Custom tags for runners | `list(string)` | `[]` | no |
| <a name="input_runner_default_disk_size"></a> [runner\_default\_disk\_size](#input\_runner\_default\_disk\_size) | Default EBS volume size in GB | `number` | `50` | no |
| <a name="input_runner_default_volume_throughput"></a> [runner\_default\_volume\_throughput](#input\_runner\_default\_volume\_throughput) | Default EBS volume throughput in MiB/s | `number` | `250` | no |
| <a name="input_runner_large_disk_size"></a> [runner\_large\_disk\_size](#input\_runner\_large\_disk\_size) | Large EBS volume size in GB | `number` | `100` | no |
| <a name="input_runner_large_volume_throughput"></a> [runner\_large\_volume\_throughput](#input\_runner\_large\_volume\_throughput) | Large EBS volume throughput in MiB/s | `number` | `500` | no |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes for runners | `number` | `360` | no |
| <a name="input_server_password"></a> [server\_password](#input\_server\_password) | Server password | `string` | `""` | no |
| <a name="input_spot_circuit_breaker"></a> [spot\_circuit\_breaker](#input\_spot\_circuit\_breaker) | Spot circuit breaker configuration | `string` | `""` | no |
| <a name="input_ssh_allowed"></a> [ssh\_allowed](#input\_ssh\_allowed) | Allow SSH access to runners | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apprunner_service_arn"></a> [apprunner\_service\_arn](#output\_apprunner\_service\_arn) | ARN of the App Runner service |
| <a name="output_apprunner_service_id"></a> [apprunner\_service\_id](#output\_apprunner\_service\_id) | ID of the App Runner service |
| <a name="output_apprunner_service_status"></a> [apprunner\_service\_status](#output\_apprunner\_service\_status) | Status of the App Runner service |
| <a name="output_apprunner_service_url"></a> [apprunner\_service\_url](#output\_apprunner\_service\_url) | URL of the App Runner service |
| <a name="output_dynamodb_locks_table_arn"></a> [dynamodb\_locks\_table\_arn](#output\_dynamodb\_locks\_table\_arn) | ARN of the DynamoDB locks table |
| <a name="output_dynamodb_locks_table_name"></a> [dynamodb\_locks\_table\_name](#output\_dynamodb\_locks\_table\_name) | Name of the DynamoDB locks table |
| <a name="output_dynamodb_workflow_jobs_table_arn"></a> [dynamodb\_workflow\_jobs\_table\_arn](#output\_dynamodb\_workflow\_jobs\_table\_arn) | ARN of the DynamoDB workflow jobs table |
| <a name="output_dynamodb_workflow_jobs_table_name"></a> [dynamodb\_workflow\_jobs\_table\_name](#output\_dynamodb\_workflow\_jobs\_table\_name) | Name of the DynamoDB workflow jobs table |
| <a name="output_eventbridge_spot_interruption_rule_arn"></a> [eventbridge\_spot\_interruption\_rule\_arn](#output\_eventbridge\_spot\_interruption\_rule\_arn) | ARN of the EventBridge spot interruption rule |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS alerts topic |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | Name of the SNS alerts topic |
| <a name="output_sqs_queue_events_url"></a> [sqs\_queue\_events\_url](#output\_sqs\_queue\_events\_url) | URL of the events SQS queue |
| <a name="output_sqs_queue_github_url"></a> [sqs\_queue\_github\_url](#output\_sqs\_queue\_github\_url) | URL of the github SQS queue |
| <a name="output_sqs_queue_housekeeping_url"></a> [sqs\_queue\_housekeeping\_url](#output\_sqs\_queue\_housekeeping\_url) | URL of the housekeeping SQS queue |
| <a name="output_sqs_queue_jobs_url"></a> [sqs\_queue\_jobs\_url](#output\_sqs\_queue\_jobs\_url) | URL of the jobs SQS queue |
| <a name="output_sqs_queue_main_arn"></a> [sqs\_queue\_main\_arn](#output\_sqs\_queue\_main\_arn) | ARN of the main SQS queue |
| <a name="output_sqs_queue_main_url"></a> [sqs\_queue\_main\_url](#output\_sqs\_queue\_main\_url) | URL of the main SQS queue |
| <a name="output_sqs_queue_pool_url"></a> [sqs\_queue\_pool\_url](#output\_sqs\_queue\_pool\_url) | URL of the pool SQS queue |
| <a name="output_sqs_queue_termination_url"></a> [sqs\_queue\_termination\_url](#output\_sqs\_queue\_termination\_url) | URL of the termination SQS queue |
<!-- END_TF_DOCS -->

## Files

- `main.tf` - Orchestration (terraform, data, locals)
- `apprunner.tf` - App Runner service and IAM
- `sqs.tf` - SQS queues and policies
- `dynamodb.tf` - DynamoDB tables
- `sns.tf` - SNS topics and subscriptions
- `eventbridge.tf` - EventBridge rules and scheduler
- `variables.tf` - Input variables
- `outputs.tf` - Output values
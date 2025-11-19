# RunsOn Terraform Module

Minimal, batteries-included Terraform/OpenTofu module for deploying [RunsOn](https://runs-on.com) infrastructure on AWS.

## Features

- **App Runner Service**: Orchestrates GitHub Actions runner provisioning and lifecycle
- **Storage**: S3 buckets for configuration, cache, and logging with lifecycle policies
- **Compute**: EC2 launch templates for Linux and Windows runners with IAM roles
- **Queuing**: SQS queues for job processing, pool management, and event handling
- **State Management**: DynamoDB tables for distributed locking and job tracking
- **Monitoring**: SNS topics for alerts, CloudWatch logs, and optional cost reports
- **Optional Components**: EFS file system and ECR repository support

## Quick Start

```hcl
module "runs_on" {
  source  = "sjysngh/runs-on/aws"
  version = "~> 1.0"

  github_organization = "my-org"
  license_key         = var.runs_on_license_key
  
  # Bring your own VPC
  vpc_id            = "vpc-123"
  public_subnet_ids = ["subnet-abc", "subnet-def"]
}
```

For a complete example, see [examples/complete](./examples/complete).

## Architecture

This module uses a **Bring Your Own VPC (BYOV)** approach. You provide the VPC and subnets, and the module creates:

- Storage layer (S3 buckets)
- Compute layer (Launch templates, IAM roles)
- Orchestration layer (App Runner, SQS, DynamoDB, SNS)
- Optional components (EFS, ECR)

## Design Principles

- **Minimal**: Only what's needed to run RunsOn
- **Batteries-included**: Works out of the box with sensible defaults
- **BYOV**: Users provide VPC/subnets (no network module)
- **Flexible**: Optional features can be enabled/disabled as needed

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

| Name | Source | Version |
|------|--------|---------|
| <a name="module_compute"></a> [compute](#module\_compute) | ./modules/compute | n/a |
| <a name="module_core"></a> [core](#module\_core) | ./modules/core | n/a |
| <a name="module_optional"></a> [optional](#module\_optional) | ./modules/optional | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ./modules/storage | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_security_group.runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.all_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_github_organization"></a> [github\_organization](#input\_github\_organization) | GitHub organization or username for RunsOn integration | `string` | n/a | yes |
| <a name="input_license_key"></a> [license\_key](#input\_license\_key) | RunsOn license key obtained from runs-on.com | `string` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet IDs for runner instances (requires at least 1) | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where RunsOn infrastructure will be deployed | `string` | n/a | yes |
| <a name="input_alert_https_endpoint"></a> [alert\_https\_endpoint](#input\_alert\_https\_endpoint) | HTTPS endpoint for alert notifications (optional) | `string` | `""` | no |
| <a name="input_alert_slack_webhook_url"></a> [alert\_slack\_webhook\_url](#input\_alert\_slack\_webhook\_url) | Slack webhook URL for alert notifications (optional) | `string` | `""` | no |
| <a name="input_app_cpu"></a> [app\_cpu](#input\_app\_cpu) | CPU units for App Runner service (256, 512, 1024, 2048, 4096) | `number` | `1024` | no |
| <a name="input_app_image"></a> [app\_image](#input\_app\_image) | App Runner container image for RunsOn service | `string` | `"public.ecr.aws/c5h5o9k1/runs-on/runs-on:v2.10.0"` | no |
| <a name="input_app_memory"></a> [app\_memory](#input\_app\_memory) | Memory in MB for App Runner service (512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288) | `number` | `2048` | no |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application version tag for RunsOn service | `string` | `"v2.10.0"` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region to deploy resources | `string` | `"us-east-1"` | no |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap script version tag | `string` | `"v0.1.12"` | no |
| <a name="input_cache_expiration_days"></a> [cache\_expiration\_days](#input\_cache\_expiration\_days) | Number of days to retain cache artifacts in S3 before expiration | `number` | `30` | no |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Name of the tag key used for cost allocation and tracking | `string` | `"CostCenter"` | no |
| <a name="input_default_admins"></a> [default\_admins](#input\_default\_admins) | Comma-separated list of default admin usernames | `string` | `""` | no |
| <a name="input_detailed_monitoring_enabled"></a> [detailed\_monitoring\_enabled](#input\_detailed\_monitoring\_enabled) | Enable detailed CloudWatch monitoring for EC2 instances (increases costs) | `bool` | `false` | no |
| <a name="input_ebs_encryption_enabled"></a> [ebs\_encryption\_enabled](#input\_ebs\_encryption\_enabled) | Enable encryption for EBS volumes on runner instances | `bool` | `true` | no |
| <a name="input_ebs_encryption_key_id"></a> [ebs\_encryption\_key\_id](#input\_ebs\_encryption\_key\_id) | KMS key ID for EBS volume encryption (leave empty for AWS managed key) | `string` | `""` | no |
| <a name="input_ec2_custom_policy_json"></a> [ec2\_custom\_policy\_json](#input\_ec2\_custom\_policy\_json) | Custom IAM policy JSON to attach to EC2 instance role (optional) | `string` | `""` | no |
| <a name="input_ec2_queue_size"></a> [ec2\_queue\_size](#input\_ec2\_queue\_size) | Maximum number of EC2 instances in queue | `number` | `50` | no |
| <a name="input_email"></a> [email](#input\_email) | Email address for alerts and notifications (requires confirmation) | `string` | `""` | no |
| <a name="input_enable_cost_reports"></a> [enable\_cost\_reports](#input\_enable\_cost\_reports) | Enable automated cost reports sent to alert email | `bool` | `true` | no |
| <a name="input_enable_ecr"></a> [enable\_ecr](#input\_enable\_ecr) | Enable ECR repository for ephemeral Docker image storage | `bool` | `false` | no |
| <a name="input_enable_efs"></a> [enable\_efs](#input\_enable\_efs) | Enable EFS file system for shared storage across runners | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., production, staging, development) | `string` | `"production"` | no |
| <a name="input_github_api_strategy"></a> [github\_api\_strategy](#input\_github\_api\_strategy) | Strategy for GitHub API calls (default, aggressive, conservative) | `string` | `"default"` | no |
| <a name="input_github_enterprise_url"></a> [github\_enterprise\_url](#input\_github\_enterprise\_url) | GitHub Enterprise Server URL (optional, leave empty for github.com) | `string` | `""` | no |
| <a name="input_integration_step_security_api_key"></a> [integration\_step\_security\_api\_key](#input\_integration\_step\_security\_api\_key) | API key for StepSecurity integration (optional) | `string` | `""` | no |
| <a name="input_ipv6_enabled"></a> [ipv6\_enabled](#input\_ipv6\_enabled) | Enable IPv6 support for runner instances | `bool` | `true` | no |
| <a name="input_linux_ami_id"></a> [linux\_ami\_id](#input\_linux\_ami\_id) | AMI ID for Linux runners (leave empty for RunsOn default) | `string` | `""` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | CloudWatch log group name for EC2 instances | `string` | `"/runs-on/ec2"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain CloudWatch logs for EC2 instances | `number` | `7` | no |
| <a name="input_logger_level"></a> [logger\_level](#input\_logger\_level) | Logging level for RunsOn service (debug, info, warn, error) | `string` | `"info"` | no |
| <a name="input_otel_exporter_endpoint"></a> [otel\_exporter\_endpoint](#input\_otel\_exporter\_endpoint) | OpenTelemetry exporter endpoint for observability (optional) | `string` | `""` | no |
| <a name="input_otel_exporter_headers"></a> [otel\_exporter\_headers](#input\_otel\_exporter\_headers) | OpenTelemetry exporter headers (optional) | `string` | `""` | no |
| <a name="input_permission_boundary_arn"></a> [permission\_boundary\_arn](#input\_permission\_boundary\_arn) | IAM permissions boundary ARN to attach to all IAM roles (optional) | `string` | `""` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs for runner instances (optional, enables private networking) | `list(string)` | `[]` | no |
| <a name="input_runner_config_auto_extends_from"></a> [runner\_config\_auto\_extends\_from](#input\_runner\_config\_auto\_extends\_from) | Auto-extend runner configuration from this base config | `string` | `""` | no |
| <a name="input_runner_custom_tags"></a> [runner\_custom\_tags](#input\_runner\_custom\_tags) | Custom tags to apply to runner instances (comma-separated list) | `list(string)` | `[]` | no |
| <a name="input_runner_default_disk_size"></a> [runner\_default\_disk\_size](#input\_runner\_default\_disk\_size) | Default EBS volume size in GB for runner instances | `number` | `50` | no |
| <a name="input_runner_default_volume_throughput"></a> [runner\_default\_volume\_throughput](#input\_runner\_default\_volume\_throughput) | Default EBS volume throughput in MiB/s (gp3 volumes only) | `number` | `400` | no |
| <a name="input_runner_large_disk_size"></a> [runner\_large\_disk\_size](#input\_runner\_large\_disk\_size) | Large EBS volume size in GB for runner instances requiring more storage | `number` | `80` | no |
| <a name="input_runner_large_volume_throughput"></a> [runner\_large\_volume\_throughput](#input\_runner\_large\_volume\_throughput) | Large EBS volume throughput in MiB/s (gp3 volumes only) | `number` | `750` | no |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes for runners before forced termination | `number` | `360` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs for runner instances and App Runner service. If empty list provided, security groups will be created automatically. | `list(string)` | `[]` | no |
| <a name="input_server_password"></a> [server\_password](#input\_server\_password) | Password for RunsOn server admin interface (optional) | `string` | `""` | no |
| <a name="input_spot_circuit_breaker"></a> [spot\_circuit\_breaker](#input\_spot\_circuit\_breaker) | Spot instance circuit breaker configuration (e.g., '5m:3' = 3 failures in 5 minutes) | `string` | `""` | no |
| <a name="input_ssh_allowed"></a> [ssh\_allowed](#input\_ssh\_allowed) | Allow SSH access to runner instances | `bool` | `false` | no |
| <a name="input_ssh_cidr_range"></a> [ssh\_cidr\_range](#input\_ssh\_cidr\_range) | CIDR range allowed for SSH access to runner instances (only applies if ssh\_allowed is true) | `string` | `"0.0.0.0/0"` | no |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Name for the RunsOn stack (used for resource naming) | `string` | `"runs-on"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_windows_ami_id"></a> [windows\_ami\_id](#input\_windows\_ami\_id) | AMI ID for Windows runners (leave empty for RunsOn default) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apprunner_service_arn"></a> [apprunner\_service\_arn](#output\_apprunner\_service\_arn) | ARN of the RunsOn App Runner service |
| <a name="output_apprunner_service_status"></a> [apprunner\_service\_status](#output\_apprunner\_service\_status) | Status of the RunsOn App Runner service |
| <a name="output_apprunner_service_url"></a> [apprunner\_service\_url](#output\_apprunner\_service\_url) | URL of the RunsOn App Runner service |
| <a name="output_aws_account_id"></a> [aws\_account\_id](#output\_aws\_account\_id) | AWS Account ID where RunsOn is deployed |
| <a name="output_aws_region"></a> [aws\_region](#output\_aws\_region) | AWS region where RunsOn is deployed |
| <a name="output_cache_bucket_arn"></a> [cache\_bucket\_arn](#output\_cache\_bucket\_arn) | ARN of the S3 cache bucket |
| <a name="output_cache_bucket_name"></a> [cache\_bucket\_name](#output\_cache\_bucket\_name) | S3 bucket name for cache storage |
| <a name="output_config_bucket_arn"></a> [config\_bucket\_arn](#output\_config\_bucket\_arn) | ARN of the S3 configuration bucket |
| <a name="output_config_bucket_name"></a> [config\_bucket\_name](#output\_config\_bucket\_name) | S3 bucket name for configuration storage |
| <a name="output_dynamodb_locks_table_name"></a> [dynamodb\_locks\_table\_name](#output\_dynamodb\_locks\_table\_name) | Name of the DynamoDB locks table |
| <a name="output_dynamodb_workflow_jobs_table_name"></a> [dynamodb\_workflow\_jobs\_table\_name](#output\_dynamodb\_workflow\_jobs\_table\_name) | Name of the DynamoDB workflow jobs table |
| <a name="output_ec2_instance_profile_arn"></a> [ec2\_instance\_profile\_arn](#output\_ec2\_instance\_profile\_arn) | ARN of the EC2 instance profile |
| <a name="output_ec2_instance_role_arn"></a> [ec2\_instance\_role\_arn](#output\_ec2\_instance\_role\_arn) | ARN of the EC2 instance IAM role |
| <a name="output_ec2_instance_role_name"></a> [ec2\_instance\_role\_name](#output\_ec2\_instance\_role\_name) | Name of the EC2 instance IAM role |
| <a name="output_ecr_repository_name"></a> [ecr\_repository\_name](#output\_ecr\_repository\_name) | Name of the ECR repository (if enabled) |
| <a name="output_ecr_repository_url"></a> [ecr\_repository\_url](#output\_ecr\_repository\_url) | URL of the ECR repository (if enabled) |
| <a name="output_effective_security_group_ids"></a> [effective\_security\_group\_ids](#output\_effective\_security\_group\_ids) | Effective security group IDs being used (created or provided) |
| <a name="output_efs_file_system_dns_name"></a> [efs\_file\_system\_dns\_name](#output\_efs\_file\_system\_dns\_name) | DNS name of the EFS file system (if enabled) |
| <a name="output_efs_file_system_id"></a> [efs\_file\_system\_id](#output\_efs\_file\_system\_id) | ID of the EFS file system (if enabled) |
| <a name="output_getting_started"></a> [getting\_started](#output\_getting\_started) | Quick start guide for using this RunsOn deployment |
| <a name="output_launch_template_linux_default_id"></a> [launch\_template\_linux\_default\_id](#output\_launch\_template\_linux\_default\_id) | ID of the Linux default launch template |
| <a name="output_launch_template_linux_private_id"></a> [launch\_template\_linux\_private\_id](#output\_launch\_template\_linux\_private\_id) | ID of the Linux private launch template (if private networking enabled) |
| <a name="output_launch_template_windows_default_id"></a> [launch\_template\_windows\_default\_id](#output\_launch\_template\_windows\_default\_id) | ID of the Windows default launch template |
| <a name="output_launch_template_windows_private_id"></a> [launch\_template\_windows\_private\_id](#output\_launch\_template\_windows\_private\_id) | ID of the Windows private launch template (if private networking enabled) |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch log group name for EC2 instances |
| <a name="output_logging_bucket_name"></a> [logging\_bucket\_name](#output\_logging\_bucket\_name) | S3 bucket name for access logs |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the EC2 resource group for cost tracking |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the created security group (null if using provided security groups) |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS alerts topic |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | Name of the SNS alerts topic |
| <a name="output_sqs_queue_events_url"></a> [sqs\_queue\_events\_url](#output\_sqs\_queue\_events\_url) | URL of the events SQS queue |
| <a name="output_sqs_queue_github_url"></a> [sqs\_queue\_github\_url](#output\_sqs\_queue\_github\_url) | URL of the GitHub SQS queue |
| <a name="output_sqs_queue_housekeeping_url"></a> [sqs\_queue\_housekeeping\_url](#output\_sqs\_queue\_housekeeping\_url) | URL of the housekeeping SQS queue |
| <a name="output_sqs_queue_jobs_url"></a> [sqs\_queue\_jobs\_url](#output\_sqs\_queue\_jobs\_url) | URL of the jobs SQS queue |
| <a name="output_sqs_queue_main_url"></a> [sqs\_queue\_main\_url](#output\_sqs\_queue\_main\_url) | URL of the main SQS queue |
| <a name="output_sqs_queue_pool_url"></a> [sqs\_queue\_pool\_url](#output\_sqs\_queue\_pool\_url) | URL of the pool SQS queue |
| <a name="output_sqs_queue_termination_url"></a> [sqs\_queue\_termination\_url](#output\_sqs\_queue\_termination\_url) | URL of the termination SQS queue |
| <a name="output_stack_name"></a> [stack\_name](#output\_stack\_name) | RunsOn stack name |
<!-- END_TF_DOCS -->

## License

MIT
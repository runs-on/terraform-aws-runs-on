# Compute Module

EC2 launch templates and IAM roles for RunsOn runners.

## What's Included

- **Launch templates** - Linux and Windows, with public/private variants
- **IAM role** - Permissions for S3, CloudWatch, SSM, EFS, and ECR
- **CloudWatch log group** - Runner logs
- **Resource group** - For cost tracking

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
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
| [aws_cloudwatch_log_group.ec2_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_instance_profile.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ec2_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ec2_cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_cloudwatch_metrics](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_create_tags](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_create_tags_volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_detailed_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_ecr_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_efs_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_get_metrics](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_read_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_snapshot_create](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_snapshot_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_snapshot_lifecycle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ec2_ecr_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ec2_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.linux_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.linux_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.windows_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.windows_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_resourcegroups_group.ec2_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID for resource ARN construction | `string` | n/a | yes |
| <a name="input_app_debug"></a> [app\_debug](#input\_app\_debug) | Enable debug mode for RunsOn stack | `bool` | n/a | yes |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application version tag | `string` | n/a | yes |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap script version tag | `string` | n/a | yes |
| <a name="input_cache_bucket_arn"></a> [cache\_bucket\_arn](#input\_cache\_bucket\_arn) | S3 bucket ARN for cache storage | `string` | n/a | yes |
| <a name="input_cache_bucket_name"></a> [cache\_bucket\_name](#input\_cache\_bucket\_name) | S3 bucket name for cache storage | `string` | n/a | yes |
| <a name="input_config_bucket_arn"></a> [config\_bucket\_arn](#input\_config\_bucket\_arn) | S3 bucket ARN for configuration storage | `string` | n/a | yes |
| <a name="input_config_bucket_name"></a> [config\_bucket\_name](#input\_config\_bucket\_name) | S3 bucket name for configuration storage | `string` | n/a | yes |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Tag key for cost allocation | `string` | n/a | yes |
| <a name="input_detailed_monitoring_enabled"></a> [detailed\_monitoring\_enabled](#input\_detailed\_monitoring\_enabled) | Enable detailed CloudWatch monitoring | `bool` | n/a | yes |
| <a name="input_ebs_encryption_enabled"></a> [ebs\_encryption\_enabled](#input\_ebs\_encryption\_enabled) | Enable EBS volume encryption | `bool` | n/a | yes |
| <a name="input_efs_file_system_id"></a> [efs\_file\_system\_id](#input\_efs\_file\_system\_id) | EFS file system ID (optional) | `string` | n/a | yes |
| <a name="input_enable_ecr"></a> [enable\_ecr](#input\_enable\_ecr) | Whether ECR is enabled | `bool` | n/a | yes |
| <a name="input_enable_efs"></a> [enable\_efs](#input\_enable\_efs) | Whether EFS is enabled | `bool` | n/a | yes |
| <a name="input_ephemeral_registry_arn"></a> [ephemeral\_registry\_arn](#input\_ephemeral\_registry\_arn) | ECR repository ARN (optional) | `string` | n/a | yes |
| <a name="input_ephemeral_registry_uri"></a> [ephemeral\_registry\_uri](#input\_ephemeral\_registry\_uri) | ECR repository URI (optional) | `string` | n/a | yes |
| <a name="input_ipv6_enabled"></a> [ipv6\_enabled](#input\_ipv6\_enabled) | Enable IPv6 for runners | `bool` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Days to retain CloudWatch logs | `number` | n/a | yes |
| <a name="input_permission_boundary_arn"></a> [permission\_boundary\_arn](#input\_permission\_boundary\_arn) | IAM permission boundary ARN | `string` | n/a | yes |
| <a name="input_private_mode"></a> [private\_mode](#input\_private\_mode) | Private networking mode: 'false', 'true', 'always', or 'only' | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region where resources are deployed | `string` | n/a | yes |
| <a name="input_runner_default_disk_size"></a> [runner\_default\_disk\_size](#input\_runner\_default\_disk\_size) | Default EBS volume size in GB | `number` | n/a | yes |
| <a name="input_runner_default_volume_throughput"></a> [runner\_default\_volume\_throughput](#input\_runner\_default\_volume\_throughput) | Default EBS volume throughput in MiB/s | `number` | n/a | yes |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes for runners | `number` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs for EC2 instances | `list(string)` | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Stack name for resource naming | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ec2_instance_profile_arn"></a> [ec2\_instance\_profile\_arn](#output\_ec2\_instance\_profile\_arn) | ARN of the EC2 instance profile |
| <a name="output_ec2_instance_profile_name"></a> [ec2\_instance\_profile\_name](#output\_ec2\_instance\_profile\_name) | Name of the EC2 instance profile |
| <a name="output_ec2_instance_role_arn"></a> [ec2\_instance\_role\_arn](#output\_ec2\_instance\_role\_arn) | ARN of the EC2 instance IAM role |
| <a name="output_ec2_instance_role_name"></a> [ec2\_instance\_role\_name](#output\_ec2\_instance\_role\_name) | Name of the EC2 instance IAM role |
| <a name="output_launch_template_linux_default_id"></a> [launch\_template\_linux\_default\_id](#output\_launch\_template\_linux\_default\_id) | ID of the Linux default launch template in format ID:Version |
| <a name="output_launch_template_linux_default_latest_version"></a> [launch\_template\_linux\_default\_latest\_version](#output\_launch\_template\_linux\_default\_latest\_version) | Latest version of the Linux default launch template |
| <a name="output_launch_template_linux_private_id"></a> [launch\_template\_linux\_private\_id](#output\_launch\_template\_linux\_private\_id) | ID of the Linux private launch template in format ID:Version |
| <a name="output_launch_template_linux_private_latest_version"></a> [launch\_template\_linux\_private\_latest\_version](#output\_launch\_template\_linux\_private\_latest\_version) | Latest version of the Linux private launch template |
| <a name="output_launch_template_windows_default_id"></a> [launch\_template\_windows\_default\_id](#output\_launch\_template\_windows\_default\_id) | ID of the Windows default launch template in format ID:Version |
| <a name="output_launch_template_windows_default_latest_version"></a> [launch\_template\_windows\_default\_latest\_version](#output\_launch\_template\_windows\_default\_latest\_version) | Latest version of the Windows default launch template |
| <a name="output_launch_template_windows_private_id"></a> [launch\_template\_windows\_private\_id](#output\_launch\_template\_windows\_private\_id) | ID of the Windows private launch template in format ID:Version |
| <a name="output_launch_template_windows_private_latest_version"></a> [launch\_template\_windows\_private\_latest\_version](#output\_launch\_template\_windows\_private\_latest\_version) | Latest version of the Windows private launch template |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | ARN of the CloudWatch log group |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the CloudWatch log group |
| <a name="output_resource_group_arn"></a> [resource\_group\_arn](#output\_resource\_group\_arn) | ARN of the EC2 resource group |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the EC2 resource group |
<!-- END_TF_DOCS -->

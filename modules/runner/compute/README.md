<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.33 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.33 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.ec2_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_instance_profile.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ec2_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ec2_bedrock_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_cloudwatch_metrics](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_create_tags](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_create_tags_volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_ecr_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_ecr_pull_through_cache_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_efs_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_get_metrics](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_read_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_snapshot_create](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_snapshot_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ec2_snapshot_lifecycle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ec2_custom](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ec2_ecr_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ec2_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.linux_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.linux_default_nested](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.linux_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.linux_private_nested](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.windows_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.windows_default_nested](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.windows_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.windows_private_nested](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_resourcegroups_group.ec2_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID for resource ARN construction | `string` | n/a | yes |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application version tag | `string` | n/a | yes |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap script version tag | `string` | n/a | yes |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Tag key for cost allocation | `string` | n/a | yes |
| <a name="input_extras"></a> [extras](#input\_extras) | Runner extras including cache, EFS, and ECR resources | <pre>object({<br/>    cache = object({<br/>      bucket_id   = string<br/>      bucket_arn  = string<br/>      bucket_name = string<br/>    })<br/>    efs = object({<br/>      enabled           = bool<br/>      file_system_id    = string<br/>      file_system_arn   = string<br/>      file_system_dns   = string<br/>      security_group_id = string<br/>    })<br/>    ecr = object({<br/>      enabled         = bool<br/>      repository_arn  = string<br/>      repository_name = string<br/>      repository_url  = string<br/>    })<br/>    pull_through_cache = object({<br/>      enabled                = bool<br/>      registry_url           = string<br/>      docker_hub_transparent = bool<br/>      rules = map(object({<br/>        ecr_repository_prefix      = string<br/>        upstream_registry_url      = string<br/>        upstream_repository_prefix = string<br/>      }))<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_ipv6_enabled"></a> [ipv6\_enabled](#input\_ipv6\_enabled) | Enable IPv6 for runners | `bool` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Days to retain CloudWatch logs | `number` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Runner networking resources | <pre>object({<br/>    vpc_id             = string<br/>    private_mode       = string<br/>    public_subnet_ids  = list(string)<br/>    private_subnet_ids = list(string)<br/>    security_group_ids = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_permission_boundary_arn"></a> [permission\_boundary\_arn](#input\_permission\_boundary\_arn) | IAM permission boundary ARN | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region where resources are deployed | `string` | n/a | yes |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes for runners | `number` | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Stack name for resource naming | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | n/a | yes |
| <a name="input_enable_bedrock"></a> [enable\_bedrock](#input\_enable\_bedrock) | Enable Amazon Bedrock access for EC2 runner instances | `bool` | `false` | no |
| <a name="input_runner_custom_policy_arn"></a> [runner\_custom\_policy\_arn](#input\_runner\_custom\_policy\_arn) | Optional managed IAM policy ARN to attach to the EC2 runner instance role | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_compute"></a> [compute](#output\_compute) | Shared runner compute resources |
<!-- END_TF_DOCS -->

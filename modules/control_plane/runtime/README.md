# ECS Runtime Service Module

Builds the shared ECS/Fargate runtime shell used by RunsOn Flex and RunsOn Fleet.

It owns the ECS cluster, execution role, log group, task definition, and ECS service. Callers provide the task role, container definitions, and placement details.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_key.ebs_encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID | `string` | n/a | yes |
| <a name="input_assign_public_ip"></a> [assign\_public\_ip](#input\_assign\_public\_ip) | Assign public IPs to tasks | `bool` | n/a | yes |
| <a name="input_cache_bucket_arn"></a> [cache\_bucket\_arn](#input\_cache\_bucket\_arn) | Cache bucket ARN | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | ECS cluster name | `string` | n/a | yes |
| <a name="input_container_definitions"></a> [container\_definitions](#input\_container\_definitions) | ECS container definitions | `any` | n/a | yes |
| <a name="input_container_insights_enabled"></a> [container\_insights\_enabled](#input\_container\_insights\_enabled) | Enable ECS container insights on the cluster | `bool` | `true` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task CPU units | `number` | n/a | yes |
| <a name="input_deployment_maximum_percent"></a> [deployment\_maximum\_percent](#input\_deployment\_maximum\_percent) | Maximum deployment percentage | `number` | `200` | no |
| <a name="input_deployment_minimum_healthy_percent"></a> [deployment\_minimum\_healthy\_percent](#input\_deployment\_minimum\_healthy\_percent) | Minimum healthy deployment percentage | `number` | `0` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Desired ECS service count | `number` | n/a | yes |
| <a name="input_ebs_encryption_key_id"></a> [ebs\_encryption\_key\_id](#input\_ebs\_encryption\_key\_id) | Optional EBS encryption key ID | `string` | `""` | no |
| <a name="input_execution_role_name"></a> [execution\_role\_name](#input\_execution\_role\_name) | Execution role name | `string` | n/a | yes |
| <a name="input_extra_task_role_statements"></a> [extra\_task\_role\_statements](#input\_extra\_task\_role\_statements) | Additional IAM statements appended to the shared task role policy | `any` | `[]` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | CloudWatch log group name | `string` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Runtime log retention in days | `number` | n/a | yes |
| <a name="input_memory"></a> [memory](#input\_memory) | Task memory in MiB | `number` | n/a | yes |
| <a name="input_platform_version"></a> [platform\_version](#input\_platform\_version) | Fargate platform version | `string` | `"LATEST"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | n/a | yes |
| <a name="input_runner_instance_role_arn"></a> [runner\_instance\_role\_arn](#input\_runner\_instance\_role\_arn) | Runner EC2 role ARN | `string` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Task security groups | `list(string)` | n/a | yes |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | ECS service name | `string` | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Stack name | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Task subnet IDs | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to runtime resources | `map(string)` | n/a | yes |
| <a name="input_task_definition_family"></a> [task\_definition\_family](#input\_task\_definition\_family) | Task definition family | `string` | n/a | yes |
| <a name="input_task_policy_name"></a> [task\_policy\_name](#input\_task\_policy\_name) | Inline policy name for the shared ECS task role | `string` | n/a | yes |
| <a name="input_task_role_managed_policy_arns"></a> [task\_role\_managed\_policy\_arns](#input\_task\_role\_managed\_policy\_arns) | Managed policy ARNs attached to the shared task role | `list(string)` | `[]` | no |
| <a name="input_task_role_name"></a> [task\_role\_name](#input\_task\_role\_name) | Shared ECS task role name | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_runtime"></a> [runtime](#output\_runtime) | Runtime ECS resources |
| <a name="output_task_role"></a> [task\_role](#output\_task\_role) | Shared ECS task role used to manage EC2 runners |
<!-- END_TF_DOCS -->

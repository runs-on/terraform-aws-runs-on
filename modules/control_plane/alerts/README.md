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
| [aws_budgets_budget.app_daily_budget](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_cloudwatch_log_group.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.slack_webhook_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_sns_topic.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sns_topic_subscription.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID allowed to publish AWS Budget notifications. | `string` | n/a | yes |
| <a name="input_email"></a> [email](#input\_email) | Email address for alerts and notifications. | `string` | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | RunsOn stack name used to name alerting resources. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to alerting resources. | `map(string)` | n/a | yes |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Cost allocation tag key whose value is the stack name; the daily budget filters on it. | `string` | `"stack"` | no |
| <a name="input_daily_budget_usd"></a> [daily\_budget\_usd](#input\_daily\_budget\_usd) | Daily AWS cost budget in USD for the stack, notifying the alert topic when actual cost exceeds it. Set to 0 to disable the budget. | `number` | `0` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Customer-managed KMS key ARN for alert topic server-side encryption. Empty leaves SSE off (SNS default disk encryption only). | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention in days for the Slack webhook Lambda. | `number` | `14` | no |
| <a name="input_permission_boundary_arn"></a> [permission\_boundary\_arn](#input\_permission\_boundary\_arn) | Optional IAM permissions boundary ARN applied to alerting roles | `string` | `""` | no |
| <a name="input_slack_webhook_url"></a> [slack\_webhook\_url](#input\_slack\_webhook\_url) | Slack webhook URL for alert notifications. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_daily_budget_name"></a> [daily\_budget\_name](#output\_daily\_budget\_name) | Daily AWS budget name when the budget is enabled. |
| <a name="output_slack_webhook_lambda_arn"></a> [slack\_webhook\_lambda\_arn](#output\_slack\_webhook\_lambda\_arn) | Slack webhook Lambda ARN when Slack alerting is enabled. |
| <a name="output_topic_arn"></a> [topic\_arn](#output\_topic\_arn) | SNS topic ARN for RunsOn alerts. |
| <a name="output_topic_name"></a> [topic\_name](#output\_topic\_name) | SNS topic name for RunsOn alerts. |
<!-- END_TF_DOCS -->

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
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.slack_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.slack_webhook_basic_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
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
| <a name="input_allow_budgets_publish"></a> [allow\_budgets\_publish](#input\_allow\_budgets\_publish) | Allow AWS Budgets in this account to publish to the alert topic. | `bool` | `false` | no |
| <a name="input_slack_webhook_url"></a> [slack\_webhook\_url](#input\_slack\_webhook\_url) | Slack webhook URL for alert notifications. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_slack_webhook_lambda_arn"></a> [slack\_webhook\_lambda\_arn](#output\_slack\_webhook\_lambda\_arn) | Slack webhook Lambda ARN when Slack alerting is enabled. |
| <a name="output_topic_arn"></a> [topic\_arn](#output\_topic\_arn) | SNS topic ARN for RunsOn alerts. |
| <a name="output_topic_name"></a> [topic\_name](#output\_topic\_name) | SNS topic name for RunsOn alerts. |
<!-- END_TF_DOCS -->

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_base_url"></a> [base\_url](#input\_base\_url) | Raw GitHub web or API URL as configured by the customer. Leave empty for github.com. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_base_url"></a> [base\_url](#output\_base\_url) | Normalized GitHub web host root URL (https://github.com for the cloud default). |
| <a name="output_enterprise_url"></a> [enterprise\_url](#output\_enterprise\_url) | Normalized enterprise web host root URL, empty for github.com. |
| <a name="output_platform"></a> [platform](#output\_platform) | GitHub platform classification: github.com, ghe.com, or ghes. |
| <a name="output_token_issuer"></a> [token\_issuer](#output\_token\_issuer) | Actions OIDC token issuer for the classified platform. |
<!-- END_TF_DOCS -->

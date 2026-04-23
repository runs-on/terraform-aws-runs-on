# RunsOn Fleet Terraform Module

Deploy RunsOn Fleet on AWS with Terraform or OpenTofu.

Public module source:

```hcl
module "runs_on_fleet" {
  source  = "runs-on/runs-on/aws//fleet"
  version = "v3.0.0"
}
```

This subtree is the Terraform surface for RunsOn Fleet. It is intentionally separate from the Flex webhook, queue, and workflow-job stack in `terraform/flex/`.

It provisions the minimum AWS primitives needed for the Fleet product surface:

- a rendered config secret for the scale-set runtime
- an ECS/Fargate runtime service and log group
- IAM for the runtime and EC2 runners
- EC2 launch templates for the runner catalog

The workflow targeting contract is:

`runs-on: runs-on/pool=<pool-name>/env=<environment>`

The stack supports one active boundary per runtime instance:

- organization mode with `github_app_id` + `github_app_private_key`
- enterprise mode with `github_enterprise_pat` + `enterprise`

Use `github_base_url` to point the runtime at GHES when needed. `pools.<pool-name>.runner_group` remains optional. The rendered runtime secret still carries the internal `github_private_key` field name because that schema is owned by `pkg/fleet`.

See [`docs/contract.md`](docs/contract.md) for the v1 contract notes and pending runtime coupling assumptions.

## Assumptions

- The runtime discovers the sole active GitHub App installation in organization mode and refreshes that binding in the background.
- Enterprise mode uses a classic PAT because enterprise-level scale-set registration does not use GitHub App auth.
- Hot and stopped counts remain part of the public pool contract; Terraform persists desired state and the runtime owns the live capacity ledger.

## Module Documentation

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.41.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_compute"></a> [compute](#module\_compute) | ../modules/runner/compute | n/a |
| <a name="module_control_plane"></a> [control\_plane](#module\_control\_plane) | ../modules/control_plane/fleet | n/a |
| <a name="module_extras"></a> [extras](#module\_extras) | ../modules/runner/extras | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../modules/runner/network | n/a |

## Resources

| Name | Type |
|------|------|

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_pools"></a> [pools](#input\_pools) | Pool catalog keyed by pool name. Entries must follow the shared config module contract. | `map(any)` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public subnet IDs used for runners and Fargate when private\_mode=false. | `list(string)` | n/a | yes |
| <a name="input_runners"></a> [runners](#input\_runners) | Runner catalog keyed by runner name. Entries must follow the shared config module contract. | `map(any)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the Fleet stack will run. | `string` | n/a | yes |
| <a name="input_app_size"></a> [app\_size](#input\_app\_size) | Preset for the Fleet worker service, default EC2 launch concurrency, and default JIT registration concurrency. Allowed values: small, medium, high, xhigh. | `string` | `"small"` | no |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application/agent tag published into the cache bucket and passed to runners. | `string` | `"v3.0.0-rc.1"` | no |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap release tag used by the shared compute bootstrap template. | `string` | `"v0.1.17"` | no |
| <a name="input_cache_expiration_days"></a> [cache\_expiration\_days](#input\_cache\_expiration\_days) | Number of days to retain cache artifacts. | `number` | `10` | no |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Tag key used for cost allocation. | `string` | `"stack"` | no |
| <a name="input_enterprise"></a> [enterprise](#input\_enterprise) | Enterprise slug used when github\_enterprise\_pat is set. | `string` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name used by the workflow targeting contract. | `string` | `"production"` | no |
| <a name="input_force_destroy_buckets"></a> [force\_destroy\_buckets](#input\_force\_destroy\_buckets) | Allow the cache bucket to be destroyed while non-empty. | `bool` | `false` | no |
| <a name="input_github_app_id"></a> [github\_app\_id](#input\_github\_app\_id) | GitHub App ID used by the Fleet runtime. | `number` | `null` | no |
| <a name="input_github_app_private_key"></a> [github\_app\_private\_key](#input\_github\_app\_private\_key) | GitHub App private key in PEM format. | `string` | `null` | no |
| <a name="input_github_base_url"></a> [github\_base\_url](#input\_github\_base\_url) | GitHub host root URL. Leave the default for github.com and set a GHES host root such as https://ghe.example.com when needed. | `string` | `"https://github.com"` | no |
| <a name="input_github_enterprise_pat"></a> [github\_enterprise\_pat](#input\_github\_enterprise\_pat) | Classic PAT used for enterprise-target Fleet mode. | `string` | `null` | no |
| <a name="input_images"></a> [images](#input\_images) | Runner image catalog keyed by image name. Entries must follow the shared config module contract. | `map(any)` | `{}` | no |
| <a name="input_ipv6_enabled"></a> [ipv6\_enabled](#input\_ipv6\_enabled) | Enable IPv6 on EC2 runner launch templates. | `bool` | `false` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention in days. | `number` | `7` | no |
| <a name="input_permission_boundary_arn"></a> [permission\_boundary\_arn](#input\_permission\_boundary\_arn) | Optional IAM permission boundary ARN applied to created roles. | `string` | `""` | no |
| <a name="input_private_mode"></a> [private\_mode](#input\_private\_mode) | Private networking mode: false, true, always, or only. | `string` | `"false"` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnet IDs used for Fargate and runners when private\_mode is enabled. | `list(string)` | `[]` | no |
| <a name="input_runner_custom_policy_arn"></a> [runner\_custom\_policy\_arn](#input\_runner\_custom\_policy\_arn) | Optional managed policy attached to the EC2 runner role. | `string` | `""` | no |
| <a name="input_runner_custom_tags"></a> [runner\_custom\_tags](#input\_runner\_custom\_tags) | Additional custom tags propagated to launched runner instances. | `list(string)` | `[]` | no |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes passed to the shared compute bootstrap template. | `number` | `60` | no |
| <a name="input_runtime_image"></a> [runtime\_image](#input\_runtime\_image) | RunsOn worker image containing the fleetd binary. Override with a runs-on-ci image for live validation. | `string` | `"public.ecr.aws/c5h5o9k1/runs-on/runs-on:v3.0.0-rc.1@sha256:7f70026c1a81dd0bda78f0b8dc8b22b9e708ac34f390535840183dab4d7a3a46"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs for runners and the Fleet worker. Leave empty to create a dedicated group. | `list(string)` | `[]` | no |
| <a name="input_ssh_allowed"></a> [ssh\_allowed](#input\_ssh\_allowed) | Allow SSH ingress when the module creates its own security group. | `bool` | `true` | no |
| <a name="input_ssh_cidr_range"></a> [ssh\_cidr\_range](#input\_ssh\_cidr\_range) | CIDR range allowed for SSH access when the module creates its own security group. | `string` | `"0.0.0.0/0"` | no |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Name of the RunsOn Fleet stack. | `string` | `"runs-on-fleet"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to all created AWS resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_config"></a> [config](#output\_config) | RunsOn Fleet runtime configuration secret |
| <a name="output_platform"></a> [platform](#output\_platform) | Shared runner platform resources for RunsOn Fleet |
| <a name="output_runtime"></a> [runtime](#output\_runtime) | RunsOn Fleet runtime ECS resources |
| <a name="output_stack"></a> [stack](#output\_stack) | RunsOn Fleet stack metadata |
| <a name="output_workflow_contract"></a> [workflow\_contract](#output\_workflow\_contract) | RunsOn Fleet workflow targeting contract |
<!-- END_TF_DOCS -->

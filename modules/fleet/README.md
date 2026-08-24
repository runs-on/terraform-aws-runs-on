# RunsOn Fleet Terraform Module

Deploy RunsOn Fleet on AWS with Terraform or OpenTofu.

RunsOn Fleet launches GitHub Actions runner scale sets from your AWS account. The Terraform module provisions the Fleet runtime, runner launch infrastructure, IAM, logging, cache storage, and rendered runtime configuration needed to create EC2 runners from GitHub assigned-job demand.

Fleet is intentionally separate from Flex. Flex receives workflow-job webhooks and launches one ephemeral runner per job. Fleet uses the GitHub runner scale set flow and targets jobs through a fleet label.

Registry pages:

- [Terraform Registry](https://registry.terraform.io/modules/runs-on/runs-on/aws)
- [OpenTofu Registry](https://search.opentofu.org/module/runs-on/runs-on/aws/latest)

This module is intended for teams that want:

- enterprise or organization-scoped GitHub runner scale sets
- ephemeral EC2 runners managed from AWS-owned infrastructure
- Terraform-managed runner groups, runtime configuration, launch templates, IAM, logs, and cache storage

Public module source:

```hcl
module "runs_on_fleet" {
  source  = "runs-on/runs-on/aws//modules/fleet"
  version = "v3.2.3"
}
```

## Minimal Enterprise Example

This example creates a GitHub Enterprise runner group with the `integrations/github` provider, deploys RunsOn Fleet into a new VPC, and attaches one Fleet capacity lane to that runner group.

Create `variables.tf`:

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name for the RunsOn Fleet stack"
  type        = string
  default     = "runs-on-fleet"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.42.0.0/20", "10.42.16.0/20"]
}

variable "github_enterprise_name" {
  description = "GitHub Enterprise slug"
  type        = string
}

variable "github_enterprise_pat" {
  description = "Classic GitHub PAT with the manage_runners:enterprise scope"
  type        = string
  sensitive   = true
}

variable "license_key" {
  description = "RunsOn license key"
  type        = string
  sensitive   = true
}

variable "email" {
  description = "Email address for Fleet alerts"
  type        = string
}
```

Create `main.tf`:

```hcl
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "github" {
  token = var.github_enterprise_pat
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.stack_name}-vpc"
  cidr = var.vpc_cidr

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = var.public_subnet_cidrs

  enable_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "github_enterprise_actions_runner_group" "runs_on" {
  name            = "${var.stack_name}-runners"
  enterprise_slug = var.github_enterprise_name

  visibility                 = "all"
  allows_public_repositories = false
}

locals {
  images = {
    ubuntu24-full-x64 = {
      name     = "runs-on-v2.2-ubuntu24-full-x64-*"
      owner    = "898082745236"
      platform = "linux"
      arch     = "x64"
    }
  }

  runners = {
    small-x64 = {
      cpu    = []
      extras = []
      family = ["t3a.micro"]
      image  = "ubuntu24-full-x64"
    }
  }

  fleets = {
    linux-small = {
      timezone     = "UTC"
      runner_group = github_enterprise_actions_runner_group.runs_on.name
      runner       = "small-x64"
      max_runners  = 200
    }
  }
}

module "runs_on_fleet" {
  source  = "runs-on/runs-on/aws//modules/fleet"
  version = "v3.2.3"

  stack_name             = var.stack_name
  github_enterprise_pat  = var.github_enterprise_pat
  github_enterprise_name = var.github_enterprise_name
  license_key            = var.license_key
  email                  = var.email
  environment            = "production"

  images  = local.images
  runners = local.runners
  fleets  = local.fleets

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnets
}

output "workflow_target_contract" {
  description = "Workflow targeting contract for this Fleet stack."
  value       = module.runs_on_fleet.workflow_contract.label
}

output "config_secret_arn" {
  description = "Rendered Fleet runtime config secret ARN."
  value       = module.runs_on_fleet.config.secret_arn
}

output "runner_group_name" {
  description = "GitHub Enterprise runner group used by Fleet."
  value       = github_enterprise_actions_runner_group.runs_on.name
}
```

The PAT must be a classic GitHub token with the `manage_runners:enterprise` scope. In enterprise mode, Fleet registers enterprise-owned runner scale sets. The enterprise runner group controls which organizations and workflows can use those runners; the fleet controls runner shape and capacity behavior.

Target a workflow with the Fleet label:

```yaml
jobs:
  build:
    runs-on: runs-on/fleet=linux-small/env=production
    steps:
      - uses: actions/checkout@v6
```

Fleet names GitHub scale sets with stack scope, so stack `runs-on-fleet-preview-v3` and fleet `linux-small` create scale set `runs-on-fleet-preview-v3-linux-small`. Fleet v1 creates runtime capacity from GitHub assigned-job demand.

Fleet validates catalog keys during planning instead of silently ignoring unsupported fields. Remove `runners.<runner-name>.debug` from Fleet catalogs. Fleet has one routing environment per stack, so remove fleet-level `env` or `environment` fields and use the module's `environment` variable instead.

Destroying the AWS stack does not necessarily delete GitHub runner scale sets. Recreating the same stack and fleet in the same runner group can reuse an existing GitHub scale set; Fleet updates its labels on startup, so verify the `fleetd` service has rolled if a changed `environment` is not reflected.

## Architecture

The Fleet root module deploys:

- a rendered config secret for the Fleet runtime and catalog
- an ECS/Fargate runtime service and log group
- IAM for the runtime and EC2 runners
- EC2 launch templates for the runner catalog
- cache storage used by runners
- networking and security-group resources when not supplied by the caller

## GitHub Boundary

The stack supports one active GitHub boundary per runtime instance:

- enterprise mode with `github_enterprise_pat` + `github_enterprise_name`
- organization mode with `github_app_id` + `github_app_private_key`

Use `github_base_url` to point the runtime at GHES when needed. In App mode, Fleet requires a GitHub App installed on exactly one organization; the runtime discovers that sole active organization installation and refreshes the binding in the background. In enterprise mode, Fleet uses a classic PAT because enterprise-level runner scale set registration does not use GitHub App auth.

`fleets.<fleet-name>.runner_group` remains optional. Multiple fleets can share the same runner group; the runner group is the GitHub access boundary, while the fleet is the capacity and runner-shape boundary.

Fleet schedule fields maintain warm EC2 standby inventory. `hot` instances stay running after warmup; `stopped` instances warm once and are stopped until demand arrives. GitHub assigned-job demand still decides when a standby instance receives a scale-set JIT runner config. Fleet uses ready hot instances first, then ready stopped instances, then cold `CreateFleet` overflow. Warm pool inventory uses on-demand EC2 capacity.

## Credential Setup URLs

Replace `<ORG>` or `<ENTERPRISE>` before opening these URLs. For GHES, replace `https://github.com` with the same host root you pass as `github_base_url`.

GitHub App organization mode:

```text
https://github.com/organizations/<ORG>/settings/apps/new?name=RunsOn%20Fleet%20%5B<ORG>%5D&url=https%3A%2F%2Fruns-on.com&public=false&webhook_active=false&organization_self_hosted_runners=write&actions=write
```

The `actions=write` repository permission lets Fleet automatically re-run jobs killed by a spot interruption (the rerun-failed-jobs API returns 403 `Resource not accessible by integration` without it) and covers the read access Fleet diagnostics use to resolve a GitHub workflow job URL to the runner name and EC2 instance for `roc logs --include console`. With read-only Actions access, Fleet still runs jobs and resolves diagnostics, but spot recovery reruns fail. Existing installs adopting spot recovery: raise Actions to Read and write in the app's permission settings, then approve the pending permission request on the organization installation.

Enterprise PAT classic mode:

```text
https://github.com/settings/tokens/new?description=RunsOn%20Fleet%20%5B<ENTERPRISE>%5D&scopes=manage_runners%3Aenterprise
```

The minimal `manage_runners:enterprise` token runs jobs but cannot call the re-run-failed-jobs API, so automatic spot recovery reruns are skipped (logged as `permission_denied`) while everything else keeps working. To enable automatic spot retries in PAT mode, add the `repo` scope to the token:

```text
https://github.com/settings/tokens/new?description=RunsOn%20Fleet%20%5B<ENTERPRISE>%5D&scopes=manage_runners%3Aenterprise,repo
```

## Runtime Config

Each fleet key maps to one fleet name and one GitHub runner scale set. The runtime names GitHub scale sets with stack scope, so stack `runs-on-fleet-preview-v3` and fleet `linux-small` create scale set `runs-on-fleet-preview-v3-linux-small`.

`app_capacity_provider` controls whether the Fleet ECS worker service runs on `fargate` or `fargate_spot`.

The rendered runtime secret still carries the internal `github_private_key` field name because that schema is owned by `pkg/fleet`.

## Ephemeral ECR Registry

Set `enable_ecr = true` to create a stack-scoped ECR repository for Docker images and BuildKit caches shared between Fleet jobs. Add `ecr-cache` to a runner's `extras` so the agent exports `RUNS_ON_ECR_CACHE` and configures Docker credentials on Linux runners.

The runner role can read and write only this generated repository. Images expire after 10 days, and the repository is force-deleted with the stack because its contents are ephemeral.

```hcl
module "runs_on_fleet" {
  source = "runs-on/runs-on/aws//modules/fleet"

  enable_ecr = true

  runners = {
    linux = {
      family = ["m7i.large"]
      image  = "ubuntu24-full-x64"
      extras = ["ecr-cache"]
    }
  }

  # Other required inputs omitted.
}
```

## ECR Pull-Through Cache

Fleet references existing ECR pull-through cache rules and prepares Linux runners with ECR Docker credentials. Create, import, or look up the account/region-level rule outside RunsOn, then pass the Terraform resource or data source object into the module. Multiple RunsOn stacks in the same account and region can safely share the same rule reference.

Every rule must use a named `ecr_repository_prefix` (the special `ROOT` prefix is rejected: it would grant runners account-wide ECR access). On Linux runners, Docker Hub references such as `docker.io/library/node:22` stay transparent for rules targeting `registry-1.docker.io`: the runs-on agent serves a local registry mirror on `127.0.0.1:6871` that maps Docker Hub paths onto the rule's prefix. It also writes the default BuildKit configuration so `docker-container` Buildx builders without an explicit config use the prefixed ECR cache directly. Buildx remote-driver workflows must remove `$HOME/.docker/buildx/buildkitd.default.toml` before creating the builder because remote daemons are configured where they run. Windows runners do not configure ECR Docker credentials or transparent Docker Hub mirroring automatically; workflows must authenticate and use explicit ECR cache paths. Configure at most one Docker Hub rule without an `upstream_repository_prefix`; additional Docker Hub rules must scope an upstream prefix and use explicit ECR image paths. Other providers use explicit ECR cache references.

```hcl
data "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = "docker-hub"
}

module "runs_on_fleet" {
  source = "runs-on/runs-on/aws//modules/fleet"

  ecr_pull_through_cache_rules = {
    docker_hub = data.aws_ecr_pull_through_cache_rule.docker_hub
  }

  runners = {
    linux = {
      family = ["m7i.large"]
      image  = "ubuntu24-full-x64"
      extras = ["s3-cache", "ecr-pull-through"]
    }
  }
}
```

You can also create the rule outside the module with `aws_ecr_pull_through_cache_rule` and pass that resource object instead of the data source.

## Main Outputs

- `stack`
- `platform`
- `runtime`
- `config`
- `workflow_contract`

## Docs

- [Contract Notes](docs/contract.md)

## Module Documentation

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.45 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.7 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.45 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_compute"></a> [compute](#module\_compute) | ../runner/compute | n/a |
| <a name="module_control_plane"></a> [control\_plane](#module\_control\_plane) | ../control_plane/fleet | n/a |
| <a name="module_extras"></a> [extras](#module\_extras) | ../runner/extras | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../runner/network | n/a |

## Resources

| Name | Type |
|------|------|
| [terraform_data.validate_public_subnets](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.validate_runner_sticky_specs](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_email"></a> [email](#input\_email) | Email address for alerts and notifications (requires confirmation) | `string` | n/a | yes |
| <a name="input_fleets"></a> [fleets](#input\_fleets) | Fleet catalog keyed by fleet name. Entries configure a runner reference and Fleet-specific settings. | `map(any)` | n/a | yes |
| <a name="input_license_key"></a> [license\_key](#input\_license\_key) | RunsOn license key obtained from runs-on.com | `string` | n/a | yes |
| <a name="input_runners"></a> [runners](#input\_runners) | Runner catalog keyed by runner name. Entries must use fields supported by Fleet's RunnerSpec. | `map(any)` | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Name of the RunsOn Fleet stack. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the Fleet stack will run. | `string` | n/a | yes |
| <a name="input_alert_slack_webhook_url"></a> [alert\_slack\_webhook\_url](#input\_alert\_slack\_webhook\_url) | Slack webhook URL for alert notifications (optional) | `string` | `""` | no |
| <a name="input_app_capacity_provider"></a> [app\_capacity\_provider](#input\_app\_capacity\_provider) | Fargate capacity provider for the Fleet worker service. Use fargate\_spot to lower idle cost for small installs; interrupted in-flight assigned jobs are reconciled by the Fleet runtime. | `string` | `"fargate"` | no |
| <a name="input_app_size"></a> [app\_size](#input\_app\_size) | Preset for the Fleet worker service, default EC2 launch concurrency, and default registration concurrency. Allowed values: small, medium, high, xhigh. | `string` | `"small"` | no |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application/agent tag published into the cache bucket and passed to runners. Passing null falls back to the default, which release publication pins to the released version. | `string` | `"v3.2.3-rc.3"` | no |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap release tag used by the shared compute bootstrap template. | `string` | `"v0.1.17"` | no |
| <a name="input_cache_bucket_namespace"></a> [cache\_bucket\_namespace](#input\_cache\_bucket\_namespace) | S3 namespace for the cache bucket. Use account-regional when an organization SCP requires account-regional S3 bucket names. | `string` | `"global"` | no |
| <a name="input_cache_bucket_versioning_enabled"></a> [cache\_bucket\_versioning\_enabled](#input\_cache\_bucket\_versioning\_enabled) | Enable S3 object versioning for the cache bucket. | `bool` | `false` | no |
| <a name="input_cache_expiration_days"></a> [cache\_expiration\_days](#input\_cache\_expiration\_days) | Number of days to retain cache artifacts. | `number` | `10` | no |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Tag key used for cost allocation. | `string` | `"stack"` | no |
| <a name="input_ecr_pull_through_cache_rules"></a> [ecr\_pull\_through\_cache\_rules](#input\_ecr\_pull\_through\_cache\_rules) | Existing ECR pull-through cache rules to reference for Fleet runner image pulls. Create or import the regional rules outside the RunsOn module. | <pre>map(object({<br/>    ecr_repository_prefix      = string<br/>    upstream_registry_url      = string<br/>    upstream_repository_prefix = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_bedrock"></a> [enable\_bedrock](#input\_enable\_bedrock) | Enable Amazon Bedrock access for EC2 runner instances. | `bool` | `false` | no |
| <a name="input_enable_cache_isolation"></a> [enable\_cache\_isolation](#input\_enable\_cache\_isolation) | Enable brokered, per-repository/per-branch credentials for Magic Cache data under scoped-cache/*. Direct S3 cache integrations keep instance-profile access to the stack-shared cache/* namespace and are not repository-isolated. Opt-in | `bool` | `false` | no |
| <a name="input_enable_ecr"></a> [enable\_ecr](#input\_enable\_ecr) | Enable an ECR repository for ephemeral Docker image and BuildKit cache storage. | `bool` | `false` | no |
| <a name="input_enable_stickydisk_isolation"></a> [enable\_stickydisk\_isolation](#input\_enable\_stickydisk\_isolation) | Remove the legacy EBS volume/snapshot permissions from the runner instance role, so all sticky-disk EBS operations happen exclusively on the control plane. Breaks the legacy v1 runs-on/snapshot action. Opt-in | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name used by the workflow targeting contract. | `string` | `"production"` | no |
| <a name="input_extra_env_vars"></a> [extra\_env\_vars](#input\_extra\_env\_vars) | Additional environment variables to set on the Fleet worker service. | `map(string)` | `{}` | no |
| <a name="input_force_destroy_buckets"></a> [force\_destroy\_buckets](#input\_force\_destroy\_buckets) | Allow the cache bucket to be destroyed while non-empty. | `bool` | `false` | no |
| <a name="input_github_app_id"></a> [github\_app\_id](#input\_github\_app\_id) | GitHub App ID used by the Fleet runtime. | `number` | `null` | no |
| <a name="input_github_app_private_key"></a> [github\_app\_private\_key](#input\_github\_app\_private\_key) | GitHub App private key in PEM format. | `string` | `null` | no |
| <a name="input_github_base_url"></a> [github\_base\_url](#input\_github\_base\_url) | GitHub host root URL. Leave the default for github.com and set a GHES host root such as https://ghe.example.com when needed. | `string` | `"https://github.com"` | no |
| <a name="input_github_enterprise_name"></a> [github\_enterprise\_name](#input\_github\_enterprise\_name) | GitHub Enterprise slug used when github\_enterprise\_pat is set. | `string` | `null` | no |
| <a name="input_github_enterprise_pat"></a> [github\_enterprise\_pat](#input\_github\_enterprise\_pat) | Classic PAT used for enterprise-target Fleet mode. Must start with ghp\_ when set. | `string` | `null` | no |
| <a name="input_images"></a> [images](#input\_images) | Custom runner image catalog keyed by image name. Built-in image names such as ubuntu24-full-x64 and ubuntu26-full-x64 do not need entries here. | `map(any)` | `{}` | no |
| <a name="input_integration_step_security_api_key"></a> [integration\_step\_security\_api\_key](#input\_integration\_step\_security\_api\_key) | API key for StepSecurity integration (optional). | `string` | `""` | no |
| <a name="input_ipv6_enabled"></a> [ipv6\_enabled](#input\_ipv6\_enabled) | Enable IPv6 on EC2 runner launch templates. | `bool` | `false` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention in days. | `number` | `7` | no |
| <a name="input_maintenance_mode"></a> [maintenance\_mode](#input\_maintenance\_mode) | Enable maintenance mode (disables queue processing and leader election) | `bool` | `false` | no |
| <a name="input_otel_exporter_endpoint"></a> [otel\_exporter\_endpoint](#input\_otel\_exporter\_endpoint) | OpenTelemetry exporter endpoint for observability (optional) | `string` | `""` | no |
| <a name="input_otel_exporter_headers"></a> [otel\_exporter\_headers](#input\_otel\_exporter\_headers) | OpenTelemetry exporter headers (optional) | `string` | `""` | no |
| <a name="input_otel_exporter_temporality"></a> [otel\_exporter\_temporality](#input\_otel\_exporter\_temporality) | OTLP metrics temporality: cumulative (default) or delta | `string` | `"cumulative"` | no |
| <a name="input_otel_logs_enabled"></a> [otel\_logs\_enabled](#input\_otel\_logs\_enabled) | Enable OpenTelemetry log export | `bool` | `true` | no |
| <a name="input_otel_traces_enabled"></a> [otel\_traces\_enabled](#input\_otel\_traces\_enabled) | Enable OpenTelemetry trace export | `bool` | `true` | no |
| <a name="input_permission_boundary_arn"></a> [permission\_boundary\_arn](#input\_permission\_boundary\_arn) | Optional IAM permission boundary ARN applied to created roles. | `string` | `""` | no |
| <a name="input_private_mode"></a> [private\_mode](#input\_private\_mode) | Private networking mode: false, true, always, or only. | `string` | `"false"` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnet IDs used for Fargate and runners when private\_mode is enabled. | `list(string)` | `[]` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public subnet IDs used for runners and Fargate. Required unless private\_mode is "only". | `list(string)` | `[]` | no |
| <a name="input_runner_custom_policy_arns"></a> [runner\_custom\_policy\_arns](#input\_runner\_custom\_policy\_arns) | Optional managed policy ARNs attached to the EC2 runner role. Use this when policy ARNs are computed by other resources. | `list(string)` | `[]` | no |
| <a name="input_runner_custom_tags"></a> [runner\_custom\_tags](#input\_runner\_custom\_tags) | Additional custom tags propagated to launched runner instances. | `list(string)` | `[]` | no |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes passed to the shared compute bootstrap template. | `number` | `60` | no |
| <a name="input_runtime_image"></a> [runtime\_image](#input\_runtime\_image) | RunsOn worker image containing the fleetd binary. Override with a runs-on-ci image for live validation. Passing null falls back to the default, which release publication pins to the released image. | `string` | `"public.ecr.aws/c5h5o9k1/runs-on/runs-on:v3.2.3-rc.3@sha256:6c2d5ede8996d875578e2fd6a5f472f89a75c7773525f1c747ec333065425e73"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs for runners and the Fleet worker. Leave empty to create a dedicated group. | `list(string)` | `[]` | no |
| <a name="input_spot_circuit_breaker"></a> [spot\_circuit\_breaker](#input\_spot\_circuit\_breaker) | Spot circuit breaker for Fleet launches, formatted as COUNT/WINDOW\_MINUTES/RECOVERY\_MINUTES: after COUNT spot interruptions within WINDOW\_MINUTES, launch on-demand for RECOVERY\_MINUTES. "false" disables it; empty uses the built-in default "2/15/30" (same semantics as the Flex SpotCircuitBreaker stack parameter). | `string` | `""` | no |
| <a name="input_ssh_allowed"></a> [ssh\_allowed](#input\_ssh\_allowed) | Allow SSH ingress when the module creates its own security group. | `bool` | `false` | no |
| <a name="input_ssh_cidr_range"></a> [ssh\_cidr\_range](#input\_ssh\_cidr\_range) | CIDR range allowed for SSH access when the module creates its own security group. | `string` | `"0.0.0.0/0"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to all created AWS resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alerts"></a> [alerts](#output\_alerts) | RunsOn Fleet alerting resources |
| <a name="output_config"></a> [config](#output\_config) | RunsOn Fleet runtime configuration secret |
| <a name="output_dashboard"></a> [dashboard](#output\_dashboard) | RunsOn Fleet CloudWatch dashboard |
| <a name="output_platform"></a> [platform](#output\_platform) | Shared runner platform resources for RunsOn Fleet |
| <a name="output_runtime"></a> [runtime](#output\_runtime) | RunsOn Fleet runtime ECS resources |
| <a name="output_stack"></a> [stack](#output\_stack) | RunsOn Fleet stack metadata |
| <a name="output_workflow_contract"></a> [workflow\_contract](#output\_workflow\_contract) | RunsOn Fleet workflow targeting contract |
<!-- END_TF_DOCS -->

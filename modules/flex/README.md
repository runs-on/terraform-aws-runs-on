# RunsOn Flex Terraform Module

Deploy RunsOn Flex on AWS with Terraform or OpenTofu.

RunsOn Flex launches ephemeral self-hosted GitHub Actions runners in your AWS account. The Terraform module provisions the Flex control plane, runner launch infrastructure, storage, queues, and operational plumbing needed to receive GitHub webhooks and start runners on demand.

Registry pages:

- [Terraform Registry](https://registry.terraform.io/modules/runs-on/runs-on/aws)
- [OpenTofu Registry](https://search.opentofu.org/module/runs-on/runs-on/aws/latest)

This module is intended for teams that want:

- ephemeral EC2 runners instead of long-lived runner servers
- AWS-owned networking, logging, and data storage
- Terraform-managed infrastructure with optional private networking, WAF, EFS, and ECR features

Public module source:

```hcl
module "runs_on_flex" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.2.0"
}
```

## Minimal Runnable Example With VPC Endpoint

Create `variables.tf`:

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on-v3"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.17.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.17.0.0/20", "10.17.16.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.17.128.0/20", "10.17.144.0/20"]
}

variable "github_organization" {
  description = "GitHub organization or username for RunsOn integration"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

variable "email" {
  description = "Email address for cost and alert reports"
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
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.stack_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = length(var.private_subnet_cidrs) > 0
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }
}

module "runs_on_flex" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.2.0"

  stack_name = var.stack_name

  github_organization = var.github_organization
  license_key         = var.license_key
  email               = var.email

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  private_mode        = "true"
  enable_efs          = true
  enable_ecr          = true
  enable_admin_routes = true
}

output "nat_ips" {
  description = "Public NAT Gateway IPs used by private runners"
  value       = module.vpc.nat_public_ips
}

output "getting_started" {
  description = "RunsOn post-apply setup instructions"
  value       = module.runs_on_flex.stack.getting_started
}
```

The S3 gateway endpoint is free and recommended for private subnet deployments. The NAT Gateway is still required because the Flex worker and runners need outbound internet access for GitHub and other public services.

## Architecture

The Flex root module deploys:

- an ECS worker service for the RunsOn control plane
- an API Gateway plus Lambda public ingress for setup, health, and webhook delivery
- an S3 cache bucket
- DynamoDB tables for locks and workflow jobs
- SQS queues for webhook, system, and event processing
- EC2 launch templates for ephemeral runners
- optional EFS, ECR, WAF, and private-networking features

## Discovery And Runtime Config

`stack_name` remains the deployment identity.

`runs-on-stack-name` is the only supported discovery tag contract. The CLI should discover the stack config secret for a stack and then use that secret plus live AWS reads.

The worker task reads a pinned stack config secret through:

- `RUNS_ON_STACK_CONFIG_SECRET_ARN`
- `RUNS_ON_STACK_CONFIG_SECRET_VERSION`

That pinned secret includes both worker runtime config and operator-facing metadata such as:

- `IngressURL`
- `ServiceLogGroupName`
- `Ec2InstanceLogGroupArn`

## Main Outputs

- `stack`
- `platform`
- `runtime`
- `ingress`
- `queues`
- `tables`
- `alerts`
- `optional_features`

## Showing The Setup URL After Apply

Terraform only prints outputs declared by the root configuration you run `terraform apply` against. The minimal example above exposes `getting_started`; print it again after apply with:

```shell
terraform output -raw getting_started
```

If you use different output names in your root module, print those names instead. For example:

```shell
terraform output -raw runs_on_getting_started
```

## Variable Naming

Inputs such as `app_size`, `app_image`, and `app_tag` configure the ECS worker service. `app_size` also sets the default webhook worker count, provisioning launch concurrency, registration concurrency, and the matching launch-related rate-limit assumptions used by the server. `RUNS_ON_APP_WEBHOOK_CONCURRENCY`, `RUNS_ON_APP_PROVISIONING_CONCURRENCY`, and `RUNS_ON_APP_REGISTRATION_CONCURRENCY` can override those worker counts through `extra_env_vars`.

## Upgrading Existing Installs Across v3.0.6

RunsOn `v3.0.6` changed the Flex control-plane ECS service from `launch_type = "FARGATE"` to an ECS capacity provider strategy so the service can run on `fargate` or `fargate_spot`.

For existing installs created before this change, the Terraform AWS provider may require a one-time forced ECS deployment when applying the upgrade. If Terraform reports:

```text
force_new_deployment should be true when capacity_provider_strategy is being updated
```

set:

```hcl
app_force_new_deployment = true
```

for one apply, then remove it or set it back to `false` after the upgrade has completed.

## Docs

- [Examples](docs/examples.md)
- [Private Networking](docs/private-networking.md)
- [WAF](docs/waf.md)
- [GitHub App Config](docs/github-app-config.md)
- [Resource Tags](docs/resource-tags.md)
- [Versioning](docs/versioning.md)

## EBS KMS Notes

If you set `ebs_encryption_key_id = "alias/aws/ebs"`, RunsOn can launch encrypted runners without any extra KMS setup.

If you set `ebs_encryption_key_id` to a customer-managed key, prefer a full key ARN, especially for cross-account keys. The generated worker task role must also be allowed to use that key:

- Role ARN shape: `arn:aws:iam::<account-id>:role/<stack-name>-service-role`
- Required for both same-account and cross-account customer-managed keys
- Cross-account keys still require manual external key-policy configuration

Minimal key-policy statement:

```json
{
  "Sid": "AllowRunsOnWorkerRole",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::<account-id>:role/<stack-name>-service-role"
  },
  "Action": [
    "kms:CreateGrant",
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:Encrypt",
    "kms:GenerateDataKey",
    "kms:GenerateDataKeyWithoutPlaintext",
    "kms:ReEncryptFrom",
    "kms:ReEncryptTo"
  ],
  "Resource": "*",
  "Condition": {
    "Bool": {
      "kms:GrantIsForAWSResource": true
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.45 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.7 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.9 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.45 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_compute"></a> [compute](#module\_compute) | ../runner/compute | n/a |
| <a name="module_control_plane"></a> [control\_plane](#module\_control\_plane) | ../control_plane/flex | n/a |
| <a name="module_extras"></a> [extras](#module\_extras) | ../runner/extras | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../runner/network | n/a |

## Resources

| Name | Type |
|------|------|
| [terraform_data.validate_public_subnets](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [time_sleep.wait_for_nat](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_email"></a> [email](#input\_email) | Email address for alerts and notifications (requires confirmation) | `string` | n/a | yes |
| <a name="input_github_organization"></a> [github\_organization](#input\_github\_organization) | GitHub organization or username for RunsOn integration | `string` | n/a | yes |
| <a name="input_license_key"></a> [license\_key](#input\_license\_key) | RunsOn license key obtained from runs-on.com | `string` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet IDs for runner instances. Required unless private\_mode is "only". | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where RunsOn infrastructure will be deployed | `string` | n/a | yes |
| <a name="input_alert_slack_webhook_url"></a> [alert\_slack\_webhook\_url](#input\_alert\_slack\_webhook\_url) | Slack webhook URL for alert notifications (optional) | `string` | `""` | no |
| <a name="input_app_budget_daily_usd"></a> [app\_budget\_daily\_usd](#input\_app\_budget\_daily\_usd) | Daily AWS cost budget in USD for this stack, filtered by the configured cost allocation tag. Set to 0 to disable the budget. For AWS Organizations member accounts, activate the cost allocation tag in the management account's Billing settings. | `number` | `10` | no |
| <a name="input_app_capacity_provider"></a> [app\_capacity\_provider](#input\_app\_capacity\_provider) | Fargate capacity provider for the RunsOn worker service. Use fargate\_spot to lower idle cost for small installs; interrupted in-flight queue messages retry after the SQS visibility timeout. | `string` | `"fargate"` | no |
| <a name="input_app_custom_policy_arns"></a> [app\_custom\_policy\_arns](#input\_app\_custom\_policy\_arns) | Optional managed IAM policy ARNs to attach to the RunsOn service role. | `list(string)` | `[]` | no |
| <a name="input_app_ecr_repository_url"></a> [app\_ecr\_repository\_url](#input\_app\_ecr\_repository\_url) | Private ECR repository URL for RunsOn image (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo:tag). When specified, the worker service will pull from this private ECR instead of public ECR. | `string` | `""` | no |
| <a name="input_app_force_new_deployment"></a> [app\_force\_new\_deployment](#input\_app\_force\_new\_deployment) | Force a new ECS deployment of the RunsOn control-plane service. Set to true for one apply when migrating existing installs across the v3.0.6 ECS capacity provider change or when changing app\_capacity\_provider. | `bool` | `false` | no |
| <a name="input_app_image"></a> [app\_image](#input\_app\_image) | Container image for the RunsOn worker service. Published module releases inject a pinned public default during mirror publication. | `string` | `"public.ecr.aws/c5h5o9k1/runs-on/runs-on:v3.2.0@sha256:5178577402c3e2445cbf465419a38f02a8c2affcbe49ccc8642453f86baa756f"` | no |
| <a name="input_app_size"></a> [app\_size](#input\_app\_size) | Preset for the worker service, default EC2 launch concurrency, and default registration concurrency. Allowed values: small, medium, high, xhigh. | `string` | `"small"` | no |
| <a name="input_app_tag"></a> [app\_tag](#input\_app\_tag) | Application version tag for RunsOn service. Published module releases inject the released default during mirror publication. | `string` | `"v3.2.0"` | no |
| <a name="input_bootstrap_tag"></a> [bootstrap\_tag](#input\_bootstrap\_tag) | Bootstrap script version tag | `string` | `"v0.1.12"` | no |
| <a name="input_cache_bucket_namespace"></a> [cache\_bucket\_namespace](#input\_cache\_bucket\_namespace) | S3 namespace for the cache bucket. Use account-regional when an organization SCP requires account-regional S3 bucket names. | `string` | `"global"` | no |
| <a name="input_cache_bucket_versioning_enabled"></a> [cache\_bucket\_versioning\_enabled](#input\_cache\_bucket\_versioning\_enabled) | Enable S3 object versioning for the cache bucket. | `bool` | `false` | no |
| <a name="input_cache_expiration_days"></a> [cache\_expiration\_days](#input\_cache\_expiration\_days) | Number of days to retain cache artifacts in S3 before expiration | `number` | `10` | no |
| <a name="input_cost_allocation_tag"></a> [cost\_allocation\_tag](#input\_cost\_allocation\_tag) | Name of the tag key used for cost allocation and tracking | `string` | `"stack"` | no |
| <a name="input_ebs_encryption_key_id"></a> [ebs\_encryption\_key\_id](#input\_ebs\_encryption\_key\_id) | KMS key ID for explicit EBS volume encryption. Leave empty to omit explicit EBS encryption fields, use alias/aws/ebs for the AWS-managed EBS key, or provide a customer-managed key ID, alias, or ARN. Prefer a full ARN for customer-managed keys, especially cross-account keys. Customer-managed keys must also trust the generated RunsOn worker task role in their key policy. | `string` | `""` | no |
| <a name="input_ecr_pull_through_cache_rules"></a> [ecr\_pull\_through\_cache\_rules](#input\_ecr\_pull\_through\_cache\_rules) | Existing ECR pull-through cache rules to reference for runner image pulls. Create or import the regional rules outside the RunsOn module. | <pre>map(object({<br/>    ecr_repository_prefix      = string<br/>    upstream_registry_url      = string<br/>    upstream_repository_prefix = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_admin_routes"></a> [enable\_admin\_routes](#input\_enable\_admin\_routes) | Enable the admin Lambda routes (`/`, `/setup`, `/setup/{proxy+}`, `/readyz`) on the public ingress | `bool` | `true` | no |
| <a name="input_enable_bedrock"></a> [enable\_bedrock](#input\_enable\_bedrock) | Enable Amazon Bedrock access for EC2 runner instances. | `bool` | `false` | no |
| <a name="input_enable_cache_isolation"></a> [enable\_cache\_isolation](#input\_enable\_cache\_isolation) | Enable brokered, per-repository/per-branch credentials for Magic Cache data under scoped-cache/*. Direct S3 cache integrations keep instance-profile access to the stack-shared cache/* namespace and are not repository-isolated. Opt-in | `bool` | `false` | no |
| <a name="input_enable_cost_reports"></a> [enable\_cost\_reports](#input\_enable\_cost\_reports) | Cost report email cadence: no, daily, weekly, or monthly. Legacy true/false values must be replaced with daily/no when upgrading. | `string` | `"daily"` | no |
| <a name="input_enable_default_dashboard"></a> [enable\_default\_dashboard](#input\_enable\_default\_dashboard) | Create the default RunsOn CloudWatch dashboard. Set to false when managing a custom dashboard separately. | `bool` | `true` | no |
| <a name="input_enable_ecr"></a> [enable\_ecr](#input\_enable\_ecr) | Enable ECR repository for ephemeral Docker image storage | `bool` | `false` | no |
| <a name="input_enable_efs"></a> [enable\_efs](#input\_enable\_efs) | Enable EFS file system for shared storage across runners | `bool` | `false` | no |
| <a name="input_enable_stickydisk_isolation"></a> [enable\_stickydisk\_isolation](#input\_enable\_stickydisk\_isolation) | Remove the legacy EBS volume/snapshot permissions from the runner instance role, so all sticky-disk EBS operations happen exclusively on the control plane. Breaks the legacy v1 runs-on/snapshot action. Opt-in | `bool` | `false` | no |
| <a name="input_enable_waf"></a> [enable\_waf](#input\_enable\_waf) | Enable AWS WAF for the public ingress | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name used for resource tagging and RunsOn job filtering. RunsOn will only process jobs with an 'env' label matching this value. See https://runs-on.com/configuration/environments/ for details. | `string` | `"production"` | no |
| <a name="input_extra_env_vars"></a> [extra\_env\_vars](#input\_extra\_env\_vars) | Additional environment variables to set on the worker service | `map(string)` | `{}` | no |
| <a name="input_force_destroy_buckets"></a> [force\_destroy\_buckets](#input\_force\_destroy\_buckets) | Allow S3 buckets to be destroyed even when not empty. Set to false for production environments to prevent accidental data loss. | `bool` | `false` | no |
| <a name="input_github_api_boost_apps"></a> [github\_api\_boost\_apps](#input\_github\_api\_boost\_apps) | Additional same-org GitHub Apps used only for API boost capacity. These entries omit webhook secrets and are written under the shared GitHub apps secret. | <pre>map(object({<br/>    github_app_id            = number<br/>    github_app_private_key   = string<br/>    github_app_client_id     = string<br/>    github_app_client_secret = string<br/>    github_app_label         = optional(string, "")<br/>  }))</pre> | `{}` | no |
| <a name="input_github_api_strategy"></a> [github\_api\_strategy](#input\_github\_api\_strategy) | Strategy for GitHub API calls (normal, conservative) | `string` | `"normal"` | no |
| <a name="input_github_app_client_id"></a> [github\_app\_client\_id](#input\_github\_app\_client\_id) | GitHub App client ID | `string` | `""` | no |
| <a name="input_github_app_client_secret"></a> [github\_app\_client\_secret](#input\_github\_app\_client\_secret) | GitHub App client secret | `string` | `""` | no |
| <a name="input_github_app_id"></a> [github\_app\_id](#input\_github\_app\_id) | GitHub App ID. If provided along with other github\_app\_* variables, creates a Secrets Manager secret and skips the web-based GitHub App setup flow. | `number` | `null` | no |
| <a name="input_github_app_private_key"></a> [github\_app\_private\_key](#input\_github\_app\_private\_key) | GitHub App private key (PEM format) | `string` | `""` | no |
| <a name="input_github_app_webhook_secret"></a> [github\_app\_webhook\_secret](#input\_github\_app\_webhook\_secret) | GitHub App webhook secret | `string` | `""` | no |
| <a name="input_github_enterprise_url"></a> [github\_enterprise\_url](#input\_github\_enterprise\_url) | GitHub Enterprise Server URL (optional, leave empty for github.com) | `string` | `""` | no |
| <a name="input_integration_step_security_api_key"></a> [integration\_step\_security\_api\_key](#input\_integration\_step\_security\_api\_key) | API key for StepSecurity integration (optional) | `string` | `""` | no |
| <a name="input_ipv6_enabled"></a> [ipv6\_enabled](#input\_ipv6\_enabled) | Enable IPv6 support for runner instances | `bool` | `false` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain CloudWatch logs for EC2 instances | `number` | `7` | no |
| <a name="input_logger_level"></a> [logger\_level](#input\_logger\_level) | Logging level for RunsOn service (debug, info, warn, error) | `string` | `"info"` | no |
| <a name="input_maintenance_mode"></a> [maintenance\_mode](#input\_maintenance\_mode) | Enable maintenance mode (disables queue processing and leader election) | `bool` | `false` | no |
| <a name="input_mandatory_extras"></a> [mandatory\_extras](#input\_mandatory\_extras) | Runner extras (e.g. s3-cache, otel) that are always enabled for every runner, regardless of label or repo config overrides. | `list(string)` | `[]` | no |
| <a name="input_otel_exporter_endpoint"></a> [otel\_exporter\_endpoint](#input\_otel\_exporter\_endpoint) | OpenTelemetry exporter endpoint for observability (optional) | `string` | `""` | no |
| <a name="input_otel_exporter_headers"></a> [otel\_exporter\_headers](#input\_otel\_exporter\_headers) | OpenTelemetry exporter headers (optional) | `string` | `""` | no |
| <a name="input_otel_exporter_temporality"></a> [otel\_exporter\_temporality](#input\_otel\_exporter\_temporality) | OTLP metrics temporality: cumulative (default) or delta | `string` | `"cumulative"` | no |
| <a name="input_otel_logs_enabled"></a> [otel\_logs\_enabled](#input\_otel\_logs\_enabled) | Enable OpenTelemetry log export | `bool` | `true` | no |
| <a name="input_otel_traces_enabled"></a> [otel\_traces\_enabled](#input\_otel\_traces\_enabled) | Enable OpenTelemetry trace export | `bool` | `true` | no |
| <a name="input_permission_boundary_arn"></a> [permission\_boundary\_arn](#input\_permission\_boundary\_arn) | IAM permissions boundary ARN to attach to all IAM roles (optional) | `string` | `""` | no |
| <a name="input_prevent_destroy_optional_resources"></a> [prevent\_destroy\_optional\_resources](#input\_prevent\_destroy\_optional\_resources) | Prevent destruction of durable optional resources such as EFS. ECR contains ephemeral runner images and is force-deleted by default. | `bool` | `true` | no |
| <a name="input_private_mode"></a> [private\_mode](#input\_private\_mode) | Private networking mode: 'false' (disabled), 'true' (opt-in with label), 'always' (default with opt-out), 'only' (forced, no public option) | `string` | `"false"` | no |
| <a name="input_private_mode_delay"></a> [private\_mode\_delay](#input\_private\_mode\_delay) | Delay before starting the worker service in private mode, to allow NAT gateways to become ready. Set to "60s" or higher for fresh NAT gateway deployments. | `string` | `"0s"` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs for runner instances (required if private\_mode is not 'false') | `list(string)` | `[]` | no |
| <a name="input_public_ingress_web_acl_arn"></a> [public\_ingress\_web\_acl\_arn](#input\_public\_ingress\_web\_acl\_arn) | Optional user-managed AWS WAFv2 Web ACL ARN to associate with the public ingress. When set, RunsOn will not manage webhook IP synchronization. | `string` | `""` | no |
| <a name="input_runner_config_auto_extends_from"></a> [runner\_config\_auto\_extends\_from](#input\_runner\_config\_auto\_extends\_from) | Auto-extend runner configuration from this base config | `string` | `".github-private"` | no |
| <a name="input_runner_custom_policy_arns"></a> [runner\_custom\_policy\_arns](#input\_runner\_custom\_policy\_arns) | Optional managed IAM policy ARNs to attach to the EC2 runner instance role. Use this when policy ARNs are computed by other resources. | `list(string)` | `[]` | no |
| <a name="input_runner_custom_tags"></a> [runner\_custom\_tags](#input\_runner\_custom\_tags) | Custom tags to apply to runner instances (comma-separated list) | `list(string)` | `[]` | no |
| <a name="input_runner_max_runtime"></a> [runner\_max\_runtime](#input\_runner\_max\_runtime) | Maximum runtime in minutes for runners before forced termination | `number` | `720` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs for runner instances and the worker service. If empty list provided, security groups will be created automatically. | `list(string)` | `[]` | no |
| <a name="input_spot_circuit_breaker"></a> [spot\_circuit\_breaker](#input\_spot\_circuit\_breaker) | Spot instance circuit breaker configuration (e.g., '2/15/30' = 2 failures in 15min, block for 30min) | `string` | `"2/15/30"` | no |
| <a name="input_ssh_allowed"></a> [ssh\_allowed](#input\_ssh\_allowed) | Allow SSH access to runner instances | `bool` | `false` | no |
| <a name="input_ssh_cidr_range"></a> [ssh\_cidr\_range](#input\_ssh\_cidr\_range) | CIDR range allowed for SSH access to runner instances (only applies if ssh\_allowed is true) | `string` | `"0.0.0.0/0"` | no |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Name for the RunsOn stack (used for resource naming) | `string` | `"runs-on"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources. Note: 'runs-on-stack-name' is added automatically for resource discovery. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alerts"></a> [alerts](#output\_alerts) | RunsOn Flex alerting resources |
| <a name="output_ingress"></a> [ingress](#output\_ingress) | RunsOn Flex public ingress endpoints |
| <a name="output_optional_features"></a> [optional\_features](#output\_optional\_features) | Optional Flex runner platform features |
| <a name="output_platform"></a> [platform](#output\_platform) | Shared runner platform resources for RunsOn Flex |
| <a name="output_queues"></a> [queues](#output\_queues) | RunsOn Flex queue resources |
| <a name="output_runtime"></a> [runtime](#output\_runtime) | RunsOn Flex runtime ECS resources |
| <a name="output_stack"></a> [stack](#output\_stack) | RunsOn Flex stack metadata and operator-facing entrypoints |
| <a name="output_tables"></a> [tables](#output\_tables) | RunsOn Flex DynamoDB tables |
<!-- END_TF_DOCS -->

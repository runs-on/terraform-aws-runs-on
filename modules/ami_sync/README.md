# ami_sync

One shared, cross-region AMI syncer that multiple RunsOn products consume.

RunsOn launches EC2 runners from **public** AMIs published by RunsOn's account
(`135269210855`) to only ~11 regions. In any other region the AMI finder fails
("no AMI found matching spec"). This module deploys a scheduled Lambda that
regularly copies the latest RunsOn AMIs from a source region into the deployment
region (tagging image **and** snapshot at create time) and prunes older copies.

The RunsOn control-plane finder queries `self` **then** the public RunsOn owner,
so once these copies exist every product running in the region resolves them
automatically — **no per-product flag, env var, or redeploy**. Deploying this
module is the single deliberate operator action. Where it is not deployed, the
finder falls back to the public RunsOn AMI exactly as before.

Deploy it **once per account+region** (its own state) regardless of how many
RunsOn products run there — see [`examples/standalone`](./examples/standalone).

## Usage

```hcl
module "ami_sync" {
  source = "runs-on/runs-on/aws//modules/ami_sync"

  enabled    = true
  stack_name = "runs-on-shared"

  # Optional: pass the product stack's tags + CMK (see "SCP-hardened accounts").
  common_tags = { Team = "platform", Environment = "production" }
  # kms_key_id  = "arn:aws:kms:<region>:<acct>:key/<id>"
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `stack_name` | string | _(required)_ | Name/tag prefix for the syncer's own resources. |
| `name_suffix` | string | `ami-sync` | Suffix appended to `stack_name`. |
| `images` | list(object) | `ubuntu24-full` x64 + arm64 | Source AMI name globs + architecture to sync/prune. |
| `source_region` | string | `us-east-1` | Region RunsOn publishes to (copy source). |
| `source_owner` | string | `135269210855` | Account owning the public RunsOn AMIs. |
| `schedule_expression` | string | `cron(30 0 * * ? *)` | Sync cadence. |
| `kms_key_id` | string | `""` | Encryption mode or key for copied snapshots (see below). |
| `retention` | number | `2` | Newest synced copies kept per family. |
| `enabled` | bool | `false` | Whether to deploy (drives `count`). |
| `common_tags` | map(string) | `{}` | Tags on module resources **and** merged into copy tags. |
| `log_retention_in_days` | number | `14` | Log group retention. |

## Outputs

| Name | Description |
|------|-------------|
| `function_arn` | AMI sync Lambda ARN (null when disabled). |
| `function_name` | AMI sync Lambda name (null when disabled). |
| `role_arn` | Lambda execution role ARN (null when disabled). |

## Choosing which images to sync (`images`)

`images` defaults to the current `ubuntu24-full` family (x64 + arm64). The Lambda
copies the most-recent source AMI matching each `name`/`architecture` and prunes
older synced copies of that same pattern down to `retention`.

**Updating the default for a new release.** When a newer family ships (e.g.
`ubuntu26-full`), maintainers should **add** it to the default rather than
replace the old one:

```hcl
default = [
  { name = "runs-on-v2.2-ubuntu24-full-x64-*",   architecture = "x86_64" },
  { name = "runs-on-v2.2-ubuntu24-full-arm64-*", architecture = "arm64" },
  { name = "runs-on-v2.2-ubuntu26-full-x64-*",   architecture = "x86_64" },
  { name = "runs-on-v2.2-ubuntu26-full-arm64-*", architecture = "arm64" },
]
```

Operators on the default (who never set `images`) pick this up on their next
`terraform apply` after bumping the module version — Terraform is pull-based, so
nothing changes until they re-apply. Operators who set their own `images` are
unaffected until they change it.

**Dropping a family.** Removing an entry stops syncing *and* pruning it; existing
copies are left in place (not deleted) and must be cleaned up manually. Prefer
keeping a retiring family in the list for one retention cycle so its stale copies
age out automatically.

**AMI prefix.** Names assume the default `RUNS_ON_AMI_PREFIX` (`runs-on-v2.2`).
If your stack overrides the prefix, override `images` to match.

## Encryption (`kms_key_id`)

Encrypting the copied snapshot is **optional**. `kms_key_id` accepts four values;
the module resolves the choice to a concrete key, grants the Lambda role the KMS
permissions, and encrypts the copy with it (no manual ARN lookup needed):

| `kms_key_id` | Behavior |
|---|---|
| `""` (default) | No explicit encryption — copies inherit the region's behavior (unencrypted, or the account default if EBS encryption-by-default is on). Runner *root volumes* are still encrypted at launch via the product's block-device override, so runtime encryption is unaffected. |
| `"default"` | Encrypt with the **region's EBS default key** (whatever EBS encryption-by-default would use). The module discovers it and grants access. |
| `"aws/ebs"` | Encrypt with the **AWS-managed EBS key**. Use when an SCP requires encryption but the managed key isn't the region default. |
| `arn:aws:kms:…` | Encrypt with that **explicit key**. |

If EBS encryption-by-default uses a customer-managed key, set
`kms_key_id = "default"` (or pass that key's ARN). AWS requires the caller to
have permission to use the selected KMS key; the empty mode does not add those
permissions automatically.

**Decrypt-at-launch** needs no extra setup for `"default"`/`"aws/ebs"`: the
EC2 / Spot / Fleet / Auto Scaling service-linked roles already have access to the
AWS-managed key, and an account-default CMK is already granted to those roles
(every encrypted volume in the account uses it). Only a *third-party* explicit CMK
would require adding key-policy use + `kms:CreateGrant` for
`AWSServiceRoleForAutoScaling` / `AWSServiceRoleForEC2SpotFleet` — in that case
reuse the same `ebs_encryption_key_id` CMK your RunsOn product uses for runner EBS
so its grants already apply. See the [EC2 Auto Scaling KMS key-policy docs](https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html).

## SCP-required tags

Pass your stack's `tags` map as `common_tags`. It is merged with the `runs-on-*`
tags and applied in the `CopyImage` `TagSpecifications` for **both image and
snapshot at create time**. Tag-on-create sets `aws:RequestTag`, which is what a
tag-enforcing SCP checks on the create call — a post-hoc `CreateTags` would be
denied because the create itself fails. The module's own resources also carry
`common_tags`.

Same-region note: if `source_region` equals the deployment region the Lambda
no-ops (nothing to copy).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.45 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.45 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.ami_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.ami_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ami_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ami_sync_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.ami_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_invocation.ami_sync_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_invocation) | resource |
| [aws_scheduler_schedule.ami_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Name/tag prefix for the syncer's own resources (role, function, log group, schedule). | `string` | n/a | yes |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Tags applied to the module's own resources AND merged into the copied image/snapshot tags at create time (pass your stack's tags map to satisfy a tag-enforcing SCP). | `map(string)` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Whether to deploy the syncer. Deploying it is a conscious operator choice (one shared syncer per account+region). | `bool` | `false` | no |
| <a name="input_images"></a> [images](#input\_images) | Images to sync. Each entry is a source AMI name glob plus architecture. The<br/>Lambda copies the most-recent matching source AMI and prunes older synced<br/>copies of the same name+architecture down to `retention`. Defaults to the<br/>current ubuntu24-full family (x64 + arm64). Names assume the default<br/>RUNS\_ON\_AMI\_PREFIX (runs-on-v2.2); override this list if your stack overrides<br/>the prefix. See README for how the default evolves across releases. | <pre>list(object({<br/>    name         = string<br/>    architecture = optional(string, "x86_64")<br/>  }))</pre> | <pre>[<br/>  {<br/>    "architecture": "x86_64",<br/>    "name": "runs-on-v2.2-ubuntu24-full-x64-*"<br/>  },<br/>  {<br/>    "architecture": "arm64",<br/>    "name": "runs-on-v2.2-ubuntu24-full-arm64-*"<br/>  }<br/>]</pre> | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | How copied snapshots are encrypted at rest. Accepts:<br/>- "" (default): no explicit encryption. Copies inherit the region's behavior<br/>  (unencrypted, or the account default if EBS encryption-by-default is on).<br/>  Runner root volumes are still encrypted at launch via the product's<br/>  block-device override, so this does not weaken runtime encryption.<br/>- "default": discover the region's EBS default key and encrypt with it. Works<br/>  whether that default is the AWS-managed key or a customer-managed CMK; the<br/>  module resolves it and grants the role the needed KMS permissions.<br/>- "aws/ebs" (or "alias/aws/ebs"): encrypt with the AWS-managed EBS key. Use<br/>  this when an SCP requires encryption but it is not the region default.<br/>- An explicit key ARN (arn:aws:kms:...:key/<id>): encrypt with that key.<br/><br/>Decrypt-at-launch needs no extra setup for the AWS-managed key or the account<br/>default CMK (the EC2/Spot/Fleet service-linked roles already have access); a<br/>different third-party CMK requires the usual key-policy/grant changes. | `string` | `""` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | CloudWatch Logs retention for the Lambda's log group. | `number` | `14` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix appended to stack\_name for this component's resource names. | `string` | `"ami-sync"` | no |
| <a name="input_retention"></a> [retention](#input\_retention) | Number of newest synced copies to keep per image family; older copies are deregistered and their snapshots deleted. | `number` | `2` | no |
| <a name="input_schedule_expression"></a> [schedule\_expression](#input\_schedule\_expression) | EventBridge Scheduler expression controlling how often the sync runs. | `string` | `"cron(30 0 * * ? *)"` | no |
| <a name="input_source_owner"></a> [source\_owner](#input\_source\_owner) | AWS account that owns the public RunsOn AMIs. | `string` | `"135269210855"` | no |
| <a name="input_source_region"></a> [source\_region](#input\_source\_region) | Region RunsOn publishes AMIs to; the copy source. The Lambda no-ops when this equals the deployment region. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_function_arn"></a> [function\_arn](#output\_function\_arn) | ARN of the AMI sync Lambda function (null when disabled). |
| <a name="output_function_name"></a> [function\_name](#output\_function\_name) | Name of the AMI sync Lambda function (null when disabled). |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the Lambda execution role (null when disabled). |
<!-- END_TF_DOCS -->

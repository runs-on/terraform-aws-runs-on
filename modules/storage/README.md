# Storage Module

Creates S3 buckets for RunsOn: config, cache, and logging.

## Features

- KMS encryption at rest
- SSL/TLS enforced
- Versioning enabled (except cache)
- Lifecycle policies for cost optimization
- Access logging
- Public access blocked

## Usage

```hcl
module "storage" {
  source = "./modules/storage"

  stack_name            = "runs-on-prod"
  cache_expiration_days = 30
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| stack_name | Stack name for resource naming | `string` | n/a | yes |
| cost_allocation_tag | Tag key for cost allocation | `string` | `"CostCenter"` | no |
| cache_expiration_days | Days to retain cache artifacts | `number` | `30` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| config_bucket_id | Config bucket ID |
| config_bucket_arn | Config bucket ARN |
| config_bucket_name | Config bucket name |
| cache_bucket_id | Cache bucket ID |
| cache_bucket_arn | Cache bucket ARN |
| cache_bucket_name | Cache bucket name |
| logging_bucket_id | Logging bucket ID |
| logging_bucket_arn | Logging bucket ARN |
| logging_bucket_name | Logging bucket name |

## Bucket Naming

Buckets are named: `{stack_name}-{type}-{account_id}`

Example: `runs-on-prod-config-123456789012`

# Basic Example

Standard RunsOn deployment with sensible defaults.

## What's Created

- VPC with 3 public subnets
- RunsOn infrastructure (App Runner, S3, SQS, DynamoDB, IAM)
- Security groups

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
tofu init && tofu apply
```

## Cleanup

```bash
tofu destroy
```

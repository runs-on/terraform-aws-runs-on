# Basic RunsOn Deployment Example

This example demonstrates the standard RunsOn deployment with all smart defaults matching the CloudFormation template.

## Features

- ✅ **Minimal configuration** - Only required variables
- ✅ **Smart defaults** - Matches CloudFormation v2.10 defaults
- ✅ **VPC creation** - Dedicated VPC with public subnets
- ✅ **Automatic security groups** - Created by the module
- ✅ **Production-ready** - Suitable for most use cases

## Prerequisites

- AWS account with appropriate permissions
- RunsOn license key from [runs-on.com](https://runs-on.com)
- OpenTofu/Terraform >= 1.6.0

## Usage

1. **Copy the example values:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Update `terraform.tfvars` with your values:**
   ```hcl
   github_organization = "your-github-org"
   license_key         = "your-license-key"
   email_address       = "your-email@example.com"
   ```

3. **Initialize and apply:**
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

## What Gets Created

- **VPC** with 3 public subnets across 3 availability zones
- **RunsOn infrastructure:**
  - App Runner service (runs-on orchestrator)
  - DynamoDB tables (locks, workflow jobs)
  - S3 buckets (config, cache, logging)
  - SQS queues (main, GitHub, DLQ)
  - IAM roles and policies
  - Security groups
  - CloudWatch log groups

## Configuration

All variables use smart defaults from the CloudFormation template. You only need to provide:

- `github_organization` - Your GitHub organization name
- `license_key` - Your RunsOn license key  
- `email_address` - Email for cost and alert reports

### Optional Customizations

If you want to customize beyond defaults, you can add variables like:

```hcl
# Enable private networking
private_subnet_cidrs = ["10.17.10.0/24", "10.17.11.0/24", "10.17.12.0/24"]

# Provide your own security groups
security_group_ids = ["sg-xxxxx"]

# See root variables.tf for all available options
```

## Outputs

After deployment, you'll see:

- `apprunner_service_url` - URL of your RunsOn service
- `getting_started` - Next steps and configuration instructions
- `config_bucket_name` - S3 bucket for configuration
- `cache_bucket_name` - S3 bucket for cache

## Next Steps

See the [full-featured](../full-featured) example to enable additional features like:
- Private networking
- EFS shared storage
- ECR ephemeral registry
- Custom runner configurations

## Cleanup

```bash
tofu destroy
```

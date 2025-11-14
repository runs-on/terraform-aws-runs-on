# Compute Module

Creates EC2 launch templates and IAM roles for RunsOn runners.

## Features

- IAM role and instance profile for EC2 instances
- Launch templates for Linux and Windows runners
- Public and private networking variants
- CloudWatch log group for runner logs
- EBS encryption support
- EFS and ECR integration (optional)
- Resource group for cost tracking

## Usage

```hcl
module "compute" {
  source = "./modules/compute"

  stack_name         = "runs-on-prod"
  security_group_ids = ["sg-123"]

  config_bucket_name = "my-config-bucket"
  config_bucket_arn  = "arn:aws:s3:::my-config-bucket"
  cache_bucket_name  = "my-cache-bucket"
  cache_bucket_arn   = "arn:aws:s3:::my-cache-bucket"
}
```

## Launch Templates

Creates 4 launch templates:
- **Linux Default** - Public networking, Ubuntu-based
- **Windows Default** - Public networking, Windows Server
- **Linux Private** - Private networking (optional)
- **Windows Private** - Private networking (optional)

## IAM Permissions

EC2 instances get permissions for:
- S3 access (config/cache buckets)
- CloudWatch logs and metrics
- EC2 snapshot management
- SSM Session Manager
- EFS mount (if enabled)
- ECR pull/push (if enabled)

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| stack_name | Stack name for resource naming | `string` | n/a | yes |
| security_group_ids | Security group IDs for EC2 instances | `list(string)` | n/a | yes |
| config_bucket_name | S3 bucket name for configuration | `string` | n/a | yes |
| config_bucket_arn | S3 bucket ARN for configuration | `string` | n/a | yes |
| cache_bucket_name | S3 bucket name for cache | `string` | n/a | yes |
| cache_bucket_arn | S3 bucket ARN for cache | `string` | n/a | yes |
| runner_default_disk_size | Default EBS volume size in GB | `number` | `50` | no |
| runner_default_volume_throughput | Default EBS throughput in MiB/s | `number` | `250` | no |
| ebs_encryption_enabled | Enable EBS volume encryption | `bool` | `true` | no |
| private_networking_enabled | Create private launch templates | `bool` | `false` | no |
| efs_file_system_id | EFS file system ID (optional) | `string` | `""` | no |
| ephemeral_registry_arn | ECR repository ARN (optional) | `string` | `""` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| ec2_instance_role_arn | IAM role ARN |
| ec2_instance_profile_arn | Instance profile ARN |
| launch_template_linux_default_id | Linux default template ID |
| launch_template_windows_default_id | Windows default template ID |
| launch_template_linux_private_id | Linux private template ID |
| launch_template_windows_private_id | Windows private template ID |
| log_group_name | CloudWatch log group name |

## User Data Scripts

Bootstrap scripts are stored in:
- `user-data-linux.sh` - Linux runner initialization
- `user-data-windows.ps1` - Windows runner initialization

These scripts:
1. Set up environment variables
2. Install AWS CLI
3. Configure CloudWatch logging
4. Mount EFS (if configured)
5. Download and run RunsOn bootstrap
# RunsOn Terraform Examples

This directory contains examples demonstrating different RunsOn deployment configurations. Each example shows how to deploy RunsOn with specific features enabled.

## Quick Start

Choose the example that best matches your needs:

| Example | Description | Monthly Cost* | Use Case |
|---------|-------------|---------------|----------|
| [basic](./basic/) | Standard deployment with smart defaults | ~$25-40 | Most users start here |
| [private-networking](./private-networking/) | Static egress IPs via NAT Gateway | ~$60-80 | Whitelist IPs, security requirements |
| [efs-enabled](./efs-enabled/) | Shared persistent storage | ~$30-50 | Cross-runner caching, monorepos |
| [ecr-enabled](./ecr-enabled/) | Docker BuildKit cache | ~$26-45 | Fast Docker builds |
| [full-featured](./full-featured/) | All features enabled | ~$150-200 | Enterprise, maximum capabilities |

*Estimated infrastructure costs only. Runner (EC2) costs are additional and usage-based.

## Examples Overview

### 1. Basic Deployment

**Path**: [`basic/`](./basic/)

The standard deployment with all smart defaults matching CloudFormation. Great starting point for most users.

**Features:**
- ✅ VPC with public subnets
- ✅ Smart defaults from CloudFormation
- ✅ Minimal configuration required
- ✅ Production-ready

**When to use:**
- First time deploying RunsOn
- Standard GitHub Actions workflows
- Cost-conscious deployments
- No special networking requirements

### 2. Private Networking

**Path**: [`private-networking/`](./private-networking/)

Enables private networking with static egress IPs via NAT Gateway.

**Features:**
- ✅ Private subnets with NAT Gateway
- ✅ Static egress IPs for whitelisting
- ✅ 4 private modes (false/true/always/only)
- ✅ VPC egress configuration

**When to use:**
- Need to whitelist IPs with external services
- Security requirements for private subnets
- Compliance needs for network isolation
- Want predictable egress IPs

**Cost impact:** +$32-97/month (NAT Gateway)

### 3. EFS Enabled

**Path**: [`efs-enabled/`](./efs-enabled/)

Shared persistent filesystem across all runners.

**Features:**
- ✅ EFS mounted at `/mnt/efs`
- ✅ Share data between runners
- ✅ Persistent cache across jobs
- ✅ 10-day lifecycle policy

**When to use:**
- Monorepo builds needing shared cache
- Cross-job artifact sharing
- Persistent test data
- Large dependency caches

**Cost impact:** +$5-15/month (storage-based)

### 4. ECR Enabled

**Path**: [`ecr-enabled/`](./ecr-enabled/)

Private container registry for Docker BuildKit cache.

**Features:**
- ✅ Private ECR repository
- ✅ BuildKit cache support
- ✅ Automatic cleanup (10 days)
- ✅ Auto-authentication for runners

**When to use:**
- Docker/container builds
- Need fast layer caching
- Multi-stage build optimization
- Want to reduce Docker Hub rate limits

**Cost impact:** +$1-10/month (storage-based)

### 5. Full Featured

**Path**: [`full-featured/`](./full-featured/)

All features enabled for maximum capabilities.

**Features:**
- ✅ Private networking (opt-in mode)
- ✅ EFS shared storage
- ✅ ECR container registry
- ✅ Multi-AZ NAT Gateways (HA)

**When to use:**
- Enterprise deployments
- Complex workflows needing all features
- Monorepo with Docker builds
- Maximum functionality needed

**Cost impact:** ~$125-175/month additional

## Common Configuration

All examples require these variables:

```hcl
github_organization = "your-github-org"  # Required
license_key         = "your-license-key"  # Required
email_address       = "your-email@example.com"  # Required
```

All other variables use smart defaults from CloudFormation v2.10.

## Getting Started

1. **Choose an example** based on your needs
2. **Navigate to the example directory:**
   ```bash
   cd examples/basic  # or private-networking, efs-enabled, etc.
   ```

3. **Copy the example tfvars:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

4. **Edit `terraform.tfvars`** with your values:
   ```hcl
   github_organization = "your-org"
   license_key         = "your-key"
   email_address       = "you@example.com"
   ```

5. **Deploy:**
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

## Cost Management

### Starting Small

Begin with the **basic** example (~$25-40/month), then enable features as needed:

```hcl
# Start basic
# ... deploy and test ...

# Add EFS later
enable_efs = true

# Add ECR when needed
enable_ecr = true

# Enable private networking if required
private_mode = "true"
```

### Cost Optimization Tips

1. **Use single NAT Gateway** instead of multi-AZ for non-HA deployments
2. **Disable unused features** - Only enable what you need
3. **Monitor storage** - EFS and ECR costs are usage-based
4. **Use lifecycle policies** - Auto-cleanup reduces storage costs
5. **Right-size runners** - Use appropriate instance types for jobs

## Feature Comparison

| Feature | Basic | Private | EFS | ECR | Full |
|---------|-------|---------|-----|-----|------|
| Public subnets | ✅ | ✅ | ✅ | ✅ | ✅ |
| Private subnets | ❌ | ✅ | ❌ | ❌ | ✅ |
| NAT Gateway | ❌ | ✅ | ❌ | ❌ | ✅ (Multi-AZ) |
| EFS storage | ❌ | ❌ | ✅ | ❌ | ✅ |
| ECR registry | ❌ | ❌ | ❌ | ✅ | ✅ |
| Static egress IPs | ❌ | ✅ | ❌ | ❌ | ✅ |
| Est. cost/month | $25-40 | $60-80 | $30-50 | $26-45 | $150-200 |

## Variable Reference

### Required Variables

All examples require:

- `github_organization` - Your GitHub org or username
- `license_key` - RunsOn license from runs-on.com
- `email_address` - Email for reports and alerts

### Optional Variables

These use smart defaults from CloudFormation:

- `aws_region` - AWS region (default: us-east-1)
- `stack_name` - Stack name (default: runs-on)
- `environment` - Environment tag (default: production)
- `vpc_id` - Your VPC ID (examples create VPCs)
- `public_subnet_ids` - Public subnet IDs (required)
- `private_subnet_ids` - Private subnet IDs (optional)
- `security_group_ids` - Security groups (auto-created if empty)

### Feature Variables

- `private_mode` - Private networking mode: "false", "true", "always", "only"
- `enable_efs` - Enable EFS shared storage (default: false)
- `enable_ecr` - Enable ECR registry (default: false)

See root [`variables.tf`](../variables.tf) for all available options.

## Network Architecture

### Basic Example
```
Internet
    │
    ├─ Internet Gateway
    │
    └─ Public Subnets (3 AZs)
           └─ Runners
```

### Private Networking Example
```
Internet
    │
    ├─ Internet Gateway
    │      │
    │      └─ Public Subnets (3 AZs)
    │
    └─ NAT Gateway (Static IP)
           │
           └─ Private Subnets (3 AZs)
                  └─ Runners
```

## Support

- **Documentation**: See individual example READMEs
- **Issues**: [GitHub Issues](https://github.com/runs-on/runs-on/issues)
- **Slack**: [RunsOn Community](https://runs-on.com/slack)
- **Docs**: [runs-on.com/docs](https://runs-on.com/docs)

## Migration from CloudFormation

If migrating from CloudFormation:

1. Start with the **basic** example
2. Match your CloudFormation parameters
3. Use the validation script to compare:
   ```bash
   ./scripts/validate-against-cfn.sh --cfn-stack your-stack --tofu-dir examples/basic
   ```

All defaults match CloudFormation v2.10 behavior.

## Next Steps

1. **Choose an example** that matches your requirements
2. **Review the README** in that example directory
3. **Deploy** following the getting started steps
4. **Monitor costs** in AWS Cost Explorer
5. **Adjust** features based on actual usage

Happy deploying! 🚀

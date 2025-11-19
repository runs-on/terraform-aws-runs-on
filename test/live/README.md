# Terragrunt Test Scenarios

This directory contains Terragrunt-managed test scenarios for comprehensive integration testing.

## Structure

```
live/
├── terragrunt.hcl       # Root configuration (common settings)
├── _shared/
│   └── vpc/             # Shared VPC for test scenarios
└── scenarios/
    ├── minimal/         # Bare minimum deployment
    ├── public-only/     # Public networking only
    ├── private-networking/ # Private + public subnets
    ├── efs-enabled/     # With EFS
    ├── ecr-enabled/     # With ECR
    └── full-featured/   # All features enabled
```

## Using Terragrunt Directly

You can deploy scenarios directly with Terragrunt (without Go tests):

### Deploy VPC

```bash
cd _shared/vpc
terragrunt apply
terragrunt output
```

### Deploy a Scenario

```bash
# Set required environment variables
export RUNS_ON_LICENSE_KEY="your-license-key"
export GITHUB_ORG="your-github-org"
export TEST_ID=$(date +%s)

# Deploy VPC first
cd _shared/vpc
terragrunt apply

# Deploy scenario
cd ../scenarios/minimal
terragrunt apply

# View outputs
terragrunt output

# Cleanup
terragrunt destroy
cd ../../_shared/vpc
terragrunt destroy
```

### Deploy All at Once

```bash
# From a scenario directory
terragrunt run-all apply

# Destroy all
terragrunt run-all destroy
```

## Scenarios

### Minimal
- Cheapest option
- Public networking only
- No EFS, no ECR
- Good for quick testing

```bash
cd scenarios/minimal
terragrunt apply
```

### Public Only
- Public subnets only
- Tests auto-created security group
- No optional features

```bash
cd scenarios/public-only
terragrunt apply
```

### Private Networking
- **Requires NAT gateway** ($32/month)
- Public + private subnets
- 4 launch templates
- VPC connector for App Runner

```bash
export ENABLE_NAT=true
cd scenarios/private-networking
terragrunt apply
```

### EFS Enabled
- Persistent file storage
- Mount targets in all AZs
- Automatic mounting in runners

```bash
cd scenarios/efs-enabled
terragrunt apply
```

### ECR Enabled
- Private container registry
- Lifecycle policy for cleanup
- Pre-configured IAM permissions

```bash
cd scenarios/ecr-enabled
terragrunt apply
```

### Full Featured
- **Most expensive** ($60-100/month base)
- All features enabled
- Private networking + EFS + ECR
- Best for comprehensive testing

```bash
export ENABLE_NAT=true
cd scenarios/full-featured
terragrunt apply
```

## Configuration

### Root Config (`terragrunt.hcl`)
- Sets AWS region
- Configures local state backend
- Auto-generates provider config
- Defines common tags
- Sets test-specific defaults

### Shared VPC
- Creates VPC with 3 AZs
- Public subnets (always)
- Private subnets (always created, but NAT only if ENABLE_NAT=true)
- DNS enabled

### Mock Outputs
Each scenario has mock outputs for `terragrunt plan`:
- Allows planning without deploying VPC
- Useful for validation

## Environment Variables

- `TEST_ID` - Unique identifier for resources (auto-generated)
- `ENABLE_NAT` - Set to "true" for private networking
- `GITHUB_ORG` - Your GitHub organization
- `RUNS_ON_LICENSE_KEY` - Your RunsOn license key
- `AWS_REGION` - AWS region (default: us-east-1)

## State Management

Each scenario uses **local state** for testing:
- State file: `terraform.tfstate` in each directory
- Easy cleanup
- No remote backend needed
- Isolated from production

## Auto-Generated Files

Terragrunt generates these files (gitignored):
- `backend.tf` - State backend configuration
- `provider.tf` - AWS provider configuration
- `.terragrunt-cache/` - Terragrunt cache

## Tips

1. **Always destroy resources** after testing to avoid costs
2. **Use TEST_ID** for unique naming to avoid conflicts
3. **Check AWS costs** regularly in Cost Explorer
4. **NAT gateways cost money** even when idle
5. **Clean up failed deployments** manually if needed

## Cleanup

```bash
# Destroy single scenario
cd scenarios/minimal
terragrunt destroy

# Destroy everything
cd scenarios/minimal  # or any scenario
terragrunt run-all destroy  # Destroys dependencies too
```

## Troubleshooting

**Dependency errors?**
- Make sure VPC is deployed first
- Check `dependency` blocks in terragrunt.hcl

**State locked?**
- Kill the lock file: `rm .terraform.tfstate.lock.info`
- Only do this if you're sure no other process is running

**Changes not applying?**
- Clear cache: `rm -rf .terragrunt-cache`
- Re-run `terragrunt apply`

**Can't destroy?**
- Some resources have `prevent_destroy` (EFS, ECR)
- Remove manually via AWS console if needed

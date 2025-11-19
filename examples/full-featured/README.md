# Full-Featured RunsOn Deployment Example

This example demonstrates deploying RunsOn with **all major features enabled** for maximum functionality.

## Features Enabled

- ✅ **Private Networking** - Static egress IPs via NAT Gateway (opt-in mode)
- ✅ **EFS Storage** - Shared persistent filesystem
- ✅ **ECR Registry** - BuildKit cache for Docker builds
- ✅ **Multi-AZ NAT** - High availability (3 NAT Gateways)
- ✅ **Smart Defaults** - All other settings match CloudFormation

## Use Cases

This configuration is ideal for:

- **Enterprise deployments** - Full feature set for production
- **Complex workflows** - Jobs that need all capabilities
- **Docker-heavy workloads** - ECR cache + EFS storage
- **Security requirements** - Static IPs for whitelisting
- **Monorepo builds** - Shared cache and artifacts

## Prerequisites

- AWS account with appropriate permissions
- RunsOn license key from [runs-on.com](https://runs-on.com)
- OpenTofu/Terraform >= 1.6.0
- **Budget awareness**: This is the most expensive configuration

## Usage

1. **Copy the example values:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Update `terraform.tfvars`:**
   ```hcl
   github_organization = "your-github-org"
   license_key         = "your-license-key"
   email_address       = "your-email@example.com"
   ```

3. **Deploy:**
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

## What Gets Created

Everything from all other examples combined:

### Networking
- VPC with 3 public + 3 private subnets across 3 AZs
- 3 NAT Gateways (one per AZ for HA)
- Internet Gateway
- Route tables and associations

### RunsOn Infrastructure
- App Runner service
- DynamoDB tables
- S3 buckets (config, cache, logging)
- SQS queues
- IAM roles and policies
- Security groups
- CloudWatch log groups

### Optional Features
- **EFS** - Shared filesystem mounted at `/mnt/efs`
- **ECR** - Private container registry with 10-day lifecycle
- **Private subnets** - For runners with `private=true` label

## Monthly Costs Estimate

**Infrastructure** (~$150-200/month):
- NAT Gateways: ~$97/month (3 x $32.40)
- App Runner: ~$25/month (baseline)
- EFS: ~$5-15/month (usage-based)
- ECR: ~$1-10/month (usage-based)  
- Data transfer: ~$10-50/month (variable)
- Other services: ~$5-10/month

**Runner costs** are additional and usage-based (EC2 instances).

### Cost Optimization

To reduce costs:

1. **Use single NAT Gateway:**
   ```hcl
   single_nat_gateway = true  # Saves ~$65/month
   ```

2. **Disable unused features:**
   ```hcl
   enable_efs = false  # Saves ~$5-15/month
   enable_ecr = false  # Saves ~$1-10/month
   ```

3. **Use opt-in private mode only when needed**

## Using All Features Together

### Example Workflow

```yaml
jobs:
  build:
    runs-on: runs-on,runner=4cpu-linux,private=true
    steps:
      - uses: actions/checkout@v4
      
      # Use EFS for persistent cache
      - name: Restore dependencies from EFS
        run: |
          if [ -d "/mnt/efs/cache/${{ github.repository }}/node_modules" ]; then
            cp -r /mnt/efs/cache/${{ github.repository }}/node_modules ./
          fi
      
      # Install and cache
      - run: npm install
      
      - name: Cache to EFS
        run: cp -r node_modules /mnt/efs/cache/${{ github.repository }}/
      
      # Build with ECR cache
      - name: Build Docker image
        run: |
          docker buildx build \
            --cache-from type=registry,ref=$RUNS_ON_ECR_REGISTRY/app:cache \
            --cache-to type=registry,ref=$RUNS_ON_ECR_REGISTRY/app:cache,mode=max \
            --tag app:${{ github.sha }} \
            .
      
      # Share artifacts via EFS
      - name: Share build output
        run: cp -r dist /mnt/efs/artifacts/${{ github.run_id }}/
  
  test:
    needs: build
    runs-on: runs-on,runner=2cpu-linux,private=true
    steps:
      - uses: actions/checkout@v4
      
      # Retrieve artifacts from EFS
      - name: Get build output
        run: cp -r /mnt/efs/artifacts/${{ github.run_id }}/dist ./
      
      - run: npm test
```

## Outputs

After deployment:

- `apprunner_service_url` - Your RunsOn service URL
- `nat_gateway_ids` - Static egress IPs (3 for HA)
- `efs_file_system_id` - Shared filesystem ID
- `ecr_repository_url` - Container registry URL
- `getting_started` - Setup instructions

## High Availability

This configuration provides:

- **Multi-AZ deployment** - Resources across 3 availability zones
- **Multiple NAT Gateways** - No single point of failure
- **EFS replication** - Data replicated across AZs
- **Auto-scaling** - App Runner scales automatically

## Cleanup

```bash
tofu destroy
```

**Important**: 
- NAT Gateway deletion takes several minutes
- EFS data is preserved - delete manually if needed
- ECR images are deleted with the repository

## Next Steps

1. **Monitor costs** - Check AWS Cost Explorer after first month
2. **Tune features** - Disable unused features to save costs
3. **Review security** - Configure security groups if needed
4. **Set up monitoring** - Use CloudWatch for observability

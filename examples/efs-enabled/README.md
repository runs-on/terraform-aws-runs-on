# EFS-Enabled RunsOn Deployment Example

This example demonstrates deploying RunsOn with **EFS (Elastic File System)** for shared persistent storage across runner instances.

## Features

- ✅ **Shared storage** - Persistent filesystem accessible by all runners
- ✅ **Cross-runner data** - Share data between different runner instances
- ✅ **Caching** - Persistent cache across job runs
- ✅ **Build artifacts** - Share build outputs between jobs

## Use Cases

- **Monorepo builds** - Share dependencies across multiple jobs
- **Persistent caching** - Cache that survives across runners
- **Shared artifacts** - Exchange data between different workflow jobs
- **Database testing** - Persistent test data

## Prerequisites

- AWS account with appropriate permissions
- RunsOn license key from [runs-on.com](https://runs-on.com)
- OpenTofu/Terraform >= 1.6.0

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

Everything from the basic example, plus:

- **EFS File System** - Shared persistent storage
- **EFS Access Point** - Mounted at `/mnt/efs` on runners
- **Mount Targets** - One per availability zone
- **Security Group Rules** - Allow NFS traffic

## Costs

**EFS Storage**: Pay for what you use
- Standard: ~$0.30/GB-month
- Infrequent Access: ~$0.025/GB-month (with lifecycle policy)

**Typical costs**: $5-20/month depending on usage

## Using EFS in Workflows

EFS is automatically mounted at `/mnt/efs` on all runners:

```yaml
jobs:
  build:
    runs-on: runs-on,runner=2cpu-linux
    steps:
      - name: Cache dependencies
        run: |
          # Store dependencies in EFS
          cp -r node_modules /mnt/efs/cache/my-project/
      
      - name: Share artifacts
        run: |
          # Share build outputs
          cp dist/* /mnt/efs/artifacts/
```

### Example: Persistent Dependency Cache

```yaml
jobs:
  install:
    runs-on: runs-on,runner=2cpu-linux
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          if [ -d "/mnt/efs/cache/${{ github.repository }}/node_modules" ]; then
            cp -r /mnt/efs/cache/${{ github.repository }}/node_modules ./
          fi
          npm install
          cp -r node_modules /mnt/efs/cache/${{ github.repository }}/
  
  test:
    needs: install
    runs-on: runs-on,runner=2cpu-linux
    steps:
      - uses: actions/checkout@v4
      - name: Restore dependencies
        run: cp -r /mnt/efs/cache/${{ github.repository }}/node_modules ./
      - run: npm test
```

## Important Notes

1. **Not a replacement for Actions cache** - Use for cross-runner sharing, not GitHub Actions cache replacement
2. **Cleanup required** - Implement your own cleanup strategy for old files
3. **Concurrent access** - Multiple runners can access simultaneously
4. **Performance** - Network filesystem, slower than local disk

## Cleanup

```bash
tofu destroy
```

**Note**: EFS data is preserved. Delete the EFS file system manually if needed.

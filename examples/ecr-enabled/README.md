# ECR-Enabled RunsOn Deployment Example

This example demonstrates deploying RunsOn with **ECR (Elastic Container Registry)** for ephemeral container image caching with Docker BuildKit.

## Features

- ✅ **Private registry** - ECR repository for container images
- ✅ **BuildKit cache** - Speed up Docker builds with layer caching
- ✅ **Automatic cleanup** - 10-day lifecycle policy
- ✅ **Auto-permissions** - Runners automatically have push/pull access

## Use Cases

- **Docker builds** - Cache Docker image layers for faster builds
- **Multi-stage builds** - Reuse intermediate build stages
- **Monorepo builds** - Share base images across projects
- **CI optimization** - Reduce build times by 50-90%

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

- **ECR Repository** - Private container registry
- **Lifecycle Policy** - Automatically deletes images after 10 days
- **IAM Permissions** - Runners can push/pull images

## Costs

**ECR Storage**: Pay for what you store
- ~$0.10/GB-month

**Typical costs**: $1-10/month depending on cache size

With 10-day lifecycle policy, cache is automatically cleaned up.

## Using ECR in Workflows

The ECR repository URL is available as an environment variable on all runners.

### Docker BuildKit Cache Example

```yaml
jobs:
  build:
    runs-on: runs-on,runner=4cpu-linux
    steps:
      - uses: actions/checkout@v4
      
      - name: Build with BuildKit cache
        run: |
          # ECR repository URL is available in $RUNS_ON_ECR_REGISTRY
          docker buildx build \
            --cache-from type=registry,ref=$RUNS_ON_ECR_REGISTRY/my-app:buildcache \
            --cache-to type=registry,ref=$RUNS_ON_ECR_REGISTRY/my-app:buildcache,mode=max \
            --tag my-app:latest \
            .
```

### Multi-stage Build Example

```yaml
jobs:
  build:
    runs-on: runs-on,runner=4cpu-linux
    steps:
      - uses: actions/checkout@v4
      
      - name: Build with inline cache
        run: |
          docker buildx build \
            --cache-from type=registry,ref=$RUNS_ON_ECR_REGISTRY/myapp:latest \
            --cache-to type=inline \
            --tag $RUNS_ON_ECR_REGISTRY/myapp:latest \
            --push \
            .
```

### Build and Push Example

```yaml
jobs:
  build:
    runs-on: runs-on,runner=4cpu-linux
    steps:
      - uses: actions/checkout@v4
      
      - name: Build and cache
        run: |
          # Runners are automatically authenticated to ECR
          docker buildx build \
            --cache-from type=registry,ref=$RUNS_ON_ECR_REGISTRY/cache:latest \
            --cache-to type=registry,ref=$RUNS_ON_ECR_REGISTRY/cache:latest,mode=max \
            --tag my-app:${{ github.sha }} \
            .
```

## Performance Benefits

Typical build time improvements:

- **First build**: Normal build time
- **Subsequent builds**: 50-90% faster (with unchanged dependencies)
- **Layer reuse**: Only rebuild changed layers

Example:
- Without cache: 5 minutes
- With ECR cache: 30 seconds (for unchanged layers)

## Cache Management

The ECR repository has a 10-day lifecycle policy that automatically:
- Keeps images pushed in the last 10 days
- Deletes older images to save costs
- Maintains reasonable cache without manual cleanup

## Important Notes

1. **Automatic authentication** - No need to run `docker login`
2. **Per-region** - ECR is region-specific
3. **Cache size** - Monitor storage costs if you have many images
4. **Lifecycle** - Images auto-expire after 10 days

## Cleanup

```bash
tofu destroy
```

**Note**: ECR repository will be deleted along with all cached images.

# ECR Example

RunsOn with private container registry for Docker BuildKit cache.

The ECR repository URL is available as `$RUNS_ON_ECR_REGISTRY` on runners.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
tofu init && tofu apply
```

## Using in Workflows

```yaml
jobs:
  build:
    runs-on: runs-on,runner=4cpu-linux
    steps:
      - uses: actions/checkout@v4
      - name: Build with cache
        run: |
          docker buildx build \
            --cache-from type=registry,ref=$RUNS_ON_ECR_REGISTRY/app:cache \
            --cache-to type=registry,ref=$RUNS_ON_ECR_REGISTRY/app:cache,mode=max \
            --tag app:${{ github.sha }} \
            .
```

## Cleanup

```bash
tofu destroy
```

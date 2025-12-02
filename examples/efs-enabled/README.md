# EFS Example

RunsOn with shared storage across all runners.

EFS is mounted at `/mnt/efs` on every runner.

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
    runs-on: runs-on,runner=2cpu-linux
    steps:
      - name: Cache to EFS
        run: cp -r node_modules /mnt/efs/cache/my-project/

      - name: Restore from EFS
        run: cp -r /mnt/efs/cache/my-project/node_modules ./
```

## Cleanup

```bash
tofu destroy
```

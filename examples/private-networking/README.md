# Private Networking Example

RunsOn with NAT Gateway for static egress IPs.

## Private Modes

| Mode | Behavior |
|------|----------|
| `"false"` | Disabled (default) |
| `"true"` | Opt-in per job with `private=true` label |
| `"always"` | All jobs private by default, opt-out with `private=false` |
| `"only"` | All jobs must run in private subnets |

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars, set private_mode = "true"
tofu init && tofu apply
```

## Using in Workflows

```yaml
jobs:
  build:
    runs-on: runs-on,runner=2cpu-linux,private=true
```

## Cleanup

```bash
tofu destroy
```

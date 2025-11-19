# Private Networking RunsOn Deployment Example

This example demonstrates deploying RunsOn with **private networking** enabled, providing static egress IPs for your runners.

## Features

- ✅ **Private subnets** - Runners launch in private subnets
- ✅ **NAT Gateway** - Provides static egress IP addresses
- ✅ **4 modes** - Flexible private networking options
- ✅ **Static IPs** - Predictable outbound IPs for whitelisting

## Private Networking Modes

The `private_mode` variable supports 4 options:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `"false"` | Disabled (default) | No private networking |
| `"true"` | Opt-in | Jobs can use `private: true` label to run in private subnets |
| `"always"` | Default with opt-out | Jobs run in private by default, use `private: false` to opt-out |
| `"only"` | Forced | All jobs must run in private subnets |

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
   private_mode        = "true"  # or "always" / "only"
   ```

3. **Deploy:**
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

## What Gets Created

Everything from the basic example, plus:

- **Private subnets** (3 across 3 AZs)
- **NAT Gateway** (provides static egress IP)
- **Route tables** for private subnet routing

## Costs

**NAT Gateway**: ~$32.40/month + data transfer costs

- For high-availability, set `single_nat_gateway = false` in main.tf (~$97.20/month for 3 NAT gateways)

## Using Private Runners

### Mode: `"true"` (Opt-in)

```yaml
jobs:
  build:
    runs-on: runs-on,runner=2cpu-linux,private=true
```

### Mode: `"always"` (Default with opt-out)

```yaml
# Runs in private by default
jobs:
  build:
    runs-on: runs-on,runner=2cpu-linux

  # Opt-out for specific jobs
  public-job:
    runs-on: runs-on,runner=2cpu-linux,private=false
```

### Mode: `"only"` (Forced)

```yaml
# All jobs automatically run in private subnets
jobs:
  build:
    runs-on: runs-on,runner=2cpu-linux
```

## Static Egress IPs

After deployment, get your static egress IP:

```bash
tofu output nat_gateway_ids
# Then check NAT Gateway public IPs in AWS Console
```

Use this IP for:
- Whitelisting in external services
- Security group rules
- Firewall configurations

## Cleanup

```bash
tofu destroy
```

**Note**: NAT Gateway deletion can take several minutes.

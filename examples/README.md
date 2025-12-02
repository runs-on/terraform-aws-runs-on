# Examples

Pick the example that matches your needs:

| Example | What it adds | Est. cost |
|---------|--------------|-----------|
| [basic](./basic/) | Standard deployment | ~$30/mo |
| [private-networking](./private-networking/) | NAT Gateway for static egress IPs | ~$65/mo |
| [efs-enabled](./efs-enabled/) | Shared storage across runners | ~$35/mo |
| [ecr-enabled](./ecr-enabled/) | Docker BuildKit cache | ~$32/mo |
| [full-featured](./full-featured/) | All features enabled | ~$175/mo |

## Getting Started

1. Pick an example
2. Copy the tfvars template:
   ```bash
   cd examples/basic
   cp terraform.tfvars.example terraform.tfvars
   ```
3. Edit `terraform.tfvars` with your values
4. Deploy:
   ```bash
   tofu init && tofu apply
   ```

## Required Variables

All examples need:
- `github_organization` - Your GitHub org or username
- `license_key` - RunsOn license from [runs-on.com](https://runs-on.com)
- `email_address` - For alerts and cost reports

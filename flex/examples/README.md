# Examples

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

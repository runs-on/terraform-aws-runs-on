# Full-Featured Example

RunsOn with all features enabled.

## What's Included

- Private networking with NAT Gateway
- EFS shared storage
- ECR container registry
- Multi-AZ for high availability

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
tofu init && tofu apply
```

## Cost Optimization

To reduce costs, disable features you don't need:

```hcl
enable_efs = false  # Save ~$10/mo
enable_ecr = false  # Save ~$5/mo
single_nat_gateway = true  # Save ~$65/mo
```

## Cleanup

```bash
tofu destroy
```

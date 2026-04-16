# Private Networking

Private networking gives runners static egress IPs via NAT Gateway, useful for IP allowlisting with third-party services.

## Mode Options

| Value | Behavior |
|-------|----------|
| `"false"` | Disabled (default). All runners launch in public subnets. |
| `"true"` | Opt-in. Runners can use `private=true` label to launch in private subnets. |
| `"always"` | Default private. All runners use private subnets unless `private=false` label is set. |
| `"only"` | Forced. All runners must use private subnets, no public option. |

## Requirements

- `private_subnet_ids` must be provided when `private_mode` is not `"false"`
- Private subnets must have a NAT Gateway for internet access
- At least one public subnet is still required (for App Runner VPC connector)

## Cost Considerations

| Resource | Approximate Cost |
|----------|-----------------|
| NAT Gateway | ~$32/mo per gateway + data transfer |
| VPC Interface Endpoints (EC2, ECR, etc.) | ~$7/mo per endpoint |
| S3 Gateway Endpoint | Free |

For fresh NAT Gateway deployments, set `private_mode_delay = "60s"` to allow the gateway to become ready before App Runner starts.

## Example

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws"
  version = "v2.12.5"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id             = "vpc-xxxxxxxx"
  public_subnet_ids  = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]
  private_subnet_ids = ["subnet-priv1", "subnet-priv2", "subnet-priv3"]

  private_mode = "true"
}
```

See the [RunsOn documentation](https://runs-on.com/networking/static-ips/) for more details.

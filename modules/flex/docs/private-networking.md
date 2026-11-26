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
- `public_subnet_ids` must be provided unless `private_mode` is `"only"`
- EFS mount targets prefer private subnets when configured, and fall back to public subnets for public-only deployments. Existing mixed public/private deployments may replace EFS mount targets after upgrading.

## Control Plane Placement

By default the control plane (the ECS Fargate worker service) follows `private_mode`: with `"false"` it runs in the public subnets with a public IP, and with any other value it runs in `private_subnet_ids` without one.

Set `control_plane_subnet_ids` to run it in subnets of your choice, without a public IP, whatever `private_mode` is. Use it to keep the control plane private while runners stay in public subnets, where jobs cannot opt in to private subnets:

```hcl
  private_mode             = "false"
  control_plane_subnet_ids = ["subnet-priv1", "subnet-priv2"]
```

Those subnets must belong to `vpc_id` and need outbound internet access for GitHub and AWS APIs, typically through a NAT Gateway. `private_mode_delay` also applies when `control_plane_subnet_ids` is set.

## Control Plane Security Groups

By default the control plane shares `security_group_ids` with the runners, so a rule that admits the runner groups (on a test database, for example) also admits the control plane.

Set `control_plane_security_group_ids` to give the control plane groups of its own. Runners keep `security_group_ids`, or the group the module creates when that list is empty:

```hcl
  control_plane_security_group_ids = [aws_security_group.runs_on_control_plane.id]
```

Those groups must belong to `vpc_id` and allow outbound access to the GitHub and AWS APIs. The service takes no inbound connections, so they need no inbound rule.

## Cost Considerations

| Resource | Approximate Cost |
|----------|-----------------|
| NAT Gateway | ~$32/mo per gateway + data transfer |
| VPC Interface Endpoints (EC2, ECR, etc.) | ~$7/mo per endpoint |
| S3 Gateway Endpoint | Free |

For fresh NAT Gateway deployments, set `private_mode_delay = "60s"` to allow the gateway to become ready before the worker service starts.

## Example

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.7.0"

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

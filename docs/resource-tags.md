# Resource Tags

All resources are tagged with `runs-on-stack-name` for discovery by the RunsOn CLI.

Key resources also have a `runs-on-resource` tag for identification:

| Tag Value | Resource |
|-----------|----------|
| `apprunner-service` | App Runner service |
| `config-bucket` | Configuration S3 bucket |
| `cache-bucket` | Cache S3 bucket |
| `logging-bucket` | Logging S3 bucket |
| `ec2-log-group` | EC2 instances CloudWatch log group |

> Do not remove these tags. They are required for RunsOn to discover and manage resources.

## Custom Tags

Use the `tags` variable to apply additional tags to all resources:

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws"
  version = "v2.12.2"

  # ...

  tags = {
    Team        = "platform"
    Environment = "production"
  }
}
```

Use `cost_allocation_tag` (default: `"stack"`) to control the tag key used for cost tracking. The value is set to the stack name.

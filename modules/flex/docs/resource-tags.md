# Resource Tags

All resources are tagged with `runs-on-stack-name` so RunsOn tooling can identify everything that belongs to the same deployment.

The stack config secret is the only tag-discovered control-plane anchor. Other resources keep the stack tag for ownership, cost allocation, and ad hoc filtering, but the CLI no longer depends on a `runs-on-resource` taxonomy.

> Do not remove `runs-on-stack-name`. It is required for deployment-agnostic discovery of the stack config secret.

## Custom Tags

Use the `tags` variable to apply additional tags to all resources:

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.0.6"

  # ...

  tags = {
    Team        = "platform"
    Environment = "production"
  }
}
```

Use `cost_allocation_tag` (default: `"stack"`) to control the tag key used for cost tracking. The value is set to the stack name.

If you rely on billing-derived features such as stack cost reports or the daily AWS budget, activate that user-defined cost allocation tag in AWS Billing. For AWS Organizations member accounts, the management account must activate the tag key.

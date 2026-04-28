# RunsOn Terraform Modules

This repository publishes the RunsOn Flex Terraform module for AWS:

- [RunsOn Flex](./flex/README.md): full webhook-driven control plane for ephemeral GitHub Actions runners

The published Terraform Registry mirror root is now a docs-only landing surface. Use the Flex submodule explicitly:

```hcl
module "runs_on_flex" {
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"
}
```

If you consume directly from Git, use the same subdirectory pattern:

```hcl
module "runs_on_flex" {
  source = "git::https://github.com/runs-on/terraform-aws-runs-on.git//flex?ref=main"
}
```

Older published tags that used the mirror root as the Flex module remain valid for those historical versions. New V3+ documentation and releases use `//flex`.

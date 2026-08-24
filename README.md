# RunsOn Terraform Modules

This repository publishes the RunsOn Terraform/OpenTofu modules for AWS.

Registry pages:

- [Terraform Registry](https://registry.terraform.io/modules/runs-on/runs-on/aws)
- [OpenTofu Registry](https://search.opentofu.org/module/runs-on/runs-on/aws/latest)

Product modules:

- [RunsOn Flex](https://github.com/runs-on/terraform-aws-runs-on/blob/release/v3.2.3/modules/flex/README.md): webhook-driven control plane for ephemeral GitHub Actions runners
- [RunsOn Fleet](https://github.com/runs-on/terraform-aws-runs-on/blob/release/v3.2.3/modules/fleet/README.md): scale-set-driven control plane for capacity-oriented runner fleets

The registry root is a landing page. Use the product module subdirectory explicitly.

## Flex

```hcl
module "runs_on_flex" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.2.3"
}
```

See the [Flex minimal runnable example](https://github.com/runs-on/terraform-aws-runs-on/blob/release/v3.2.3/modules/flex/README.md#minimal-runnable-example-with-vpc-endpoint).

## Fleet

```hcl
module "runs_on_fleet" {
  source  = "runs-on/runs-on/aws//modules/fleet"
  version = "v3.2.3"
}
```

See the [Fleet minimal enterprise example](https://github.com/runs-on/terraform-aws-runs-on/blob/release/v3.2.3/modules/fleet/README.md#minimal-enterprise-example).

## Git Source

If you consume directly from Git, use the same subdirectory pattern:

```hcl
module "runs_on_flex" {
  source = "git::https://github.com/runs-on/terraform-aws-runs-on.git//modules/flex?ref=release/v3.2.3"
}

module "runs_on_fleet" {
  source = "git::https://github.com/runs-on/terraform-aws-runs-on.git//modules/fleet?ref=release/v3.2.3"
}
```

Older published tags that used the mirror root or `//flex` path remain valid for those historical versions. Current documentation and releases use `//modules/flex` and `//modules/fleet`.

# Versioning

This module is released from the RunsOn monorepo and uses the same tag as the canonical product version. Flex publishes as the Registry-visible `//modules/flex` submodule in the downstream mirror.

```
v{MAJOR}.{MINOR}.{PATCH}
```

## Release Model

- The source of truth is the monorepo root `VERSION` file.
- The downstream repository `runs-on/terraform-aws-runs-on` is a mirror published from that monorepo.
- The public mirror root is a landing page. Consume the Flex module from `runs-on/runs-on/aws//modules/flex`.
- The monorepo copy intentionally leaves `app_image` and `app_tag` blank.
- The mirrored public repo receives a pinned `app_image` plus matching `app_tag` during mirror publication after the release image exists.

## Upgrading

1. Check the RunsOn changelog at [runs-on.com/changelog](https://runs-on.com/changelog).
2. Check the Terraform module [release notes](https://github.com/runs-on/terraform-aws-runs-on/releases).
3. Update your module version pin to the desired `vX.Y.Z` release tag.

## Using A Git Branch

To use this module from a specific git branch (for example `main`):

```hcl
module "runs-on" {
  source = "git::https://github.com/runs-on/terraform-aws-runs-on.git//modules/flex?ref=main"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]
}
```

Replace `main` with any branch name, tag, or commit SHA.

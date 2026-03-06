# Versioning

This module follows a versioning scheme that maps to the main RunsOn application version:

```
v{MAJOR}.{MINOR}.{PATCH}-r{REVISION}
```

- **`v{MAJOR}.{MINOR}.{PATCH}`** matches the compatible RunsOn application version
- **`-r{REVISION}`** is an independent Terraform module revision (r1, r2, r3, etc.)

## Examples

| Version | Meaning |
|---------|---------|
| `v2.11.0-r1` | First Terraform release for RunsOn v2.11.0 |
| `v2.11.0-r2` | Second Terraform release (bug fixes, improvements) |
| `v2.12.0-r1` | First Terraform release for RunsOn v2.12.0 |

## Upgrading

1. Check the RunsOn changelog at [runs-on.com/changelog](https://runs-on.com/changelog)
2. Check the Terraform module [release notes](https://github.com/runs-on/terraform-aws-runs-on/releases)

## Using a Git Branch

To use this module from a specific git branch (e.g., `main`):

```hcl
module "runs-on" {
  source = "git::https://github.com/runs-on/terraform-aws-runs-on.git?ref=main"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]
}
```

Replace `main` with any branch name, tag, or commit SHA.

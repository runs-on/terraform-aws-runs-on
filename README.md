# RunsOn OpenTofu Module

Minimal, batteries-included OpenTofu module for deploying [RunsOn](https://runs-on.com) infrastructure on AWS.

## Status

🚧 **Work in Progress** - Currently building out the modules.

### Completed
- ✅ Development tooling setup (Makefile, pre-commit, linting)
- ✅ Storage module (S3 buckets for config/cache/logging)

### In Progress
- 🔨 Compute module (EC2 launch templates, IAM roles)
- 🔨 Core module (App Runner, SQS, DynamoDB, SNS)

### Planned
- ⏳ Optional modules (EFS, ECR)
- ⏳ Root module composition
- ⏳ Examples
- ⏳ CI/CD

## Quick Start

```hcl
module "runs_on" {
  source  = "your-org/runs-on/aws"
  version = "~> 1.0"

  github_organization = "my-org"
  license_key        = var.runs_on_license_key
  
  # Bring your own networking
  vpc_id             = "vpc-123"
  public_subnet_ids  = ["subnet-abc", "subnet-def"]
  security_group_ids = ["sg-123"]
}
```

## Module Structure

```
runs-on-tf/
├── modules/
│   ├── storage/    # S3 buckets (DONE)
│   ├── compute/    # EC2 launch templates, IAM
│   ├── core/       # App Runner, SQS, DynamoDB
│   └── optional/   # EFS, ECR
├── examples/
│   └── minimal/
└── main.tf         # Root module
```

## Development

See [QUICKSTART.md](QUICKSTART.md) for development workflow.

```bash
# Fast validation (< 20 sec)
make quick

# Watch mode
make watch

# Full plan
tofu plan
```

## Design Principles

- **Minimal**: Only what's needed to run RunsOn
- **Batteries-included**: Works out of the box with sensible defaults
- **BYO Networking**: Users provide VPC/subnets (no network module)
- **Fast feedback**: Validate in seconds, not minutes

## Requirements

- OpenTofu >= 1.6.0 (or Terraform >= 1.5.0)
- AWS provider >= 5.0
- Existing VPC with subnets

## License

MIT
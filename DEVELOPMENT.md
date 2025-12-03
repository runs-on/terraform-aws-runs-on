# Development Guide

## Prerequisites

Install development tools (macOS):
```bash
make install-tools
```

Or manually install: `opentofu`, `tflint`, `tfsec`, `terraform-docs`

For tests, install [mise](https://mise.jdx.dev/) to manage Go version:
```bash
cd test && mise install
```

## Development Workflow

### Quick Checks
```bash
make quick       # fmt-check + validate + lint
make pre-commit  # quick + security scan
```

### Individual Commands
```bash
make fmt         # Format all .tf files
make validate    # Validate OpenTofu syntax
make lint        # Run TFLint
make security    # Run tfsec
make docs        # Regenerate module READMEs
```

## Testing

Tests use [Terratest](https://terratest.gruntwork.io/) and deploy real AWS infrastructure.

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_ACCESS_KEY_ID` | Yes | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | Yes | AWS credentials |
| `RUNS_ON_LICENSE_KEY` | Yes | RunsOn license key |
| `AWS_REGION` | No | Defaults to `us-east-1` |
| `GITHUB_ORG` | No | GitHub org for tests |
| `RUNS_ON_TEST_REPO` | No | For integration tests (`owner/repo` format) |
| `GITHUB_TOKEN` | No | For integration tests |

### Running Tests

```bash
# Run basic scenario (default)
make test

# Run specific scenarios
make test-basic    # Standard deployment
make test-efs      # With EFS shared storage
make test-ecr      # With ECR registry
make test-private  # With NAT gateway (expensive)
make test-full     # All features (expensive)

# Run all scenarios
make test-all

# Skip expensive scenarios
make test-short
```

### Test Scenarios

| Command | Test | Cost |
|---------|------|------|
| `make test-basic` | `TestScenarioBasic` | Low |
| `make test-efs` | `TestScenarioEFSEnabled` | Low |
| `make test-ecr` | `TestScenarioECREnabled` | Low |
| `make test-private` | `TestScenarioPrivateNetworking` | High (NAT) |
| `make test-full` | `TestScenarioFullFeatured` | High (NAT + EFS + ECR) |

### Test Structure

Each scenario test:
1. Deploys a VPC fixture (`test/fixtures/vpc/`)
2. Deploys the runs-on root module
3. Runs validations:
   - **Output validations** - Check expected outputs exist
   - **Security validations** - S3 encryption, public access blocking, IAM permissions
   - **Compliance validations** - Versioning, log retention
   - **Functional validations** - Launch EC2, verify S3/EFS/ECR access via SSM
4. Cleans up (deferred destroy)

### Test Helpers

Key files in `test/`:
- `scenarios_test.go` - Test scenarios
- `helpers.go` - AWS SDK helpers, validation functions, SSM command execution

## Cleanup

```bash
make clean  # Remove .terraform, tfstate, tfplan files
```

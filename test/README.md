# RunsOn Terraform Module Tests

This directory contains comprehensive tests for the runs-on Terraform module using Terratest and Terragrunt.

## Quick Start

```bash
# Install dependencies
go mod download

# Run all tests (requires AWS credentials)
export AWS_PROFILE=your-test-profile
export RUNS_ON_LICENSE_KEY=your-license
export GITHUB_ORG=your-org

# Run tests
go test -v -timeout 90m ./...

# Run only fast tests (skip expensive NAT gateway tests)
go test -v -short -timeout 30m ./...
```

## Test Organization

### Unit Tests (`*_test.go`)
- `storage_test.go` - S3 bucket creation and configuration
- `optional_test.go` - EFS and ECR feature flags
- `compute_test.go` - Skipped (use scenarios instead)
- `core_test.go` - Skipped (use scenarios instead)

### Integration Tests
- `integration_test.go` - Full stack tests (not yet implemented)
- `scenarios_test.go` - End-to-end scenario tests with Terragrunt

### Test Fixtures (`fixtures/`)
Simple Terraform configurations for unit testing individual modules.

### Test Scenarios (`live/scenarios/`)
Terragrunt-managed complete deployments for integration testing:
- `minimal/` - Bare minimum configuration
- `public-only/` - Public networking only
- `private-networking/` - Private + public subnets (requires NAT)
- `efs-enabled/` - With EFS file system
- `ecr-enabled/` - With ECR repository
- `full-featured/` - All features enabled (most expensive)

## Common Commands

```bash
# Run specific test
go test -v -run TestStorageModuleBucketCreation -timeout 30m

# Run all storage tests
go test -v -run TestStorage -timeout 30m

# Run specific scenario
go test -v -run TestScenarioMinimal -timeout 30m

# Run all scenarios except expensive ones
go test -v -short -run TestScenario -timeout 45m

# Clean up after failed test
cd fixtures/storage && terraform destroy
cd live/scenarios/minimal && terragrunt destroy
```

## Environment Variables

Required:
- `AWS_ACCESS_KEY_ID` or `AWS_PROFILE` - AWS credentials
- `AWS_SECRET_ACCESS_KEY` - If using access keys
- `RUNS_ON_LICENSE_KEY` - Your RunsOn license (or "test-key" for fixtures)
- `GITHUB_ORG` - Your GitHub organization (or "test-org" for fixtures)

Optional:
- `AWS_REGION` - Default: us-east-1
- `TEST_ID` - Unique ID for test resources (auto-generated if not set)
- `ENABLE_NAT` - Set to "true" for private networking tests

## Test Costs

Be aware of AWS costs when running tests:

| Test | Duration | ~Cost | Notes |
|------|----------|-------|-------|
| Storage module | 5-10 min | $0.50-1 | Safe to run frequently |
| Optional module | 5-10 min | $0.50-1 | Safe to run frequently |
| Minimal scenario | 15-20 min | $2-5 | Moderate cost |
| EFS scenario | 20-30 min | $3-7 | Moderate cost |
| Private networking | 30-45 min | $10-15 | **Expensive** (NAT gateway) |
| Full-featured | 45-60 min | $15-25 | **Most expensive** |

**Tip**: Use `go test -short` to skip expensive tests during development.

## CI/CD

Tests run automatically in GitHub Actions on:
- Pull requests
- Pushes to main branch

See `../.github/workflows/terratest.yml` for configuration.

## Troubleshooting

**Tests timeout?**
```bash
go test -v -timeout 120m ./...
```

**Resources not cleaned up?**
```bash
cd live/scenarios/minimal
terragrunt destroy
```

**Can't find Terragrunt?**
```bash
brew install terragrunt
```

## More Information

See [TESTING.md](../TESTING.md) in the root directory for comprehensive testing documentation.

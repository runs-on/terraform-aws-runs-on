# Testing Guide

This document describes how to test the runs-on Terraform module using Terratest and Terragrunt.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Test Structure](#test-structure)
- [Running Tests](#running-tests)
- [Test Categories](#test-categories)
- [Writing Tests](#writing-tests)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

1. **Go** (1.21 or later)
   ```bash
   # macOS
   brew install go
   
   # Verify
   go version
   ```

2. **Terraform** (1.6 or later)
   ```bash
   # macOS
   brew install terraform
   
   # Verify
   terraform version
   ```

3. **Terragrunt** (0.54 or later)
   ```bash
   # macOS
   brew install terragrunt
   
   # Verify
   terragrunt --version
   ```

### AWS Configuration

1. **AWS Account**: You need an AWS account for testing
2. **AWS Credentials**: Configure via environment variables or AWS CLI
   ```bash
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_REGION="us-east-1"
   
   # Or use AWS CLI
   aws configure
   ```

3. **Required Environment Variables**:
   ```bash
   export RUNS_ON_LICENSE_KEY="your-license-key"
   export GITHUB_ORG="your-github-org"
   ```

### Go Dependencies

```bash
cd test
go mod download
```

## Quick Start

### Run All Tests

```bash
cd test
go test -v -timeout 90m ./...
```

### Run Specific Test Suite

```bash
# Storage module tests only
go test -v -timeout 30m -run TestStorage

# Scenario tests only
go test -v -timeout 45m -run TestScenario

# Single test
go test -v -timeout 30m -run TestStorageModuleBucketCreation
```

### Run Tests in Short Mode (Skip Expensive Tests)

```bash
go test -v -short -timeout 30m ./...
```

## Test Structure

```
test/
├── *_test.go           # Test files
├── helpers.go          # Shared test helpers
├── fixtures/           # Simple Terraform fixtures for unit tests
│   ├── storage/
│   ├── compute/
│   ├── core/
│   └── optional/
└── live/               # Terragrunt-managed scenario tests
    ├── terragrunt.hcl  # Root config
    ├── _shared/vpc/    # Shared VPC for tests
    └── scenarios/      # Test scenarios
        ├── minimal/
        ├── public-only/
        ├── private-networking/
        ├── efs-enabled/
        ├── ecr-enabled/
        └── full-featured/
```

## Running Tests

### Unit Tests (Module-Level)

Test individual modules in isolation:

```bash
# Storage module (no dependencies)
go test -v -run TestStorage -timeout 30m

# Optional module (minimal dependencies)
go test -v -run TestOptional -timeout 30m
```

**Note**: Compute and Core module unit tests are skipped because they require dependencies. Use scenario tests instead.

### Scenario Tests (Integration-Level)

Test complete deployments with Terragrunt:

```bash
# Minimal scenario (cheapest, fastest)
go test -v -run TestScenarioMinimal -timeout 30m

# Public networking only
go test -v -run TestScenarioPublicOnly -timeout 30m

# EFS enabled
go test -v -run TestScenarioEFSEnabled -timeout 45m

# ECR enabled
go test -v -run TestScenarioECREnabled -timeout 30m

# Private networking (requires NAT - expensive!)
go test -v -run TestScenarioPrivateNetworking -timeout 45m

# Full-featured (most expensive - all features)
go test -v -run TestScenarioFullFeatured -timeout 60m
```

### Integration Tests

```bash
# Full stack integration (not yet implemented)
go test -v -run TestIntegration -timeout 60m
```

## Test Categories

### 1. Unit Tests (Fast, Cheap)

- **Purpose**: Test individual modules in isolation
- **Cost**: Low (~$1-5 per run)
- **Duration**: 5-15 minutes
- **Examples**:
  - Storage module bucket creation
  - Optional module feature flags
  
```bash
go test -v -run "TestStorage|TestOptional" -timeout 30m
```

### 2. Scenario Tests (Medium Speed, Medium Cost)

- **Purpose**: Test realistic deployment scenarios
- **Cost**: Medium (~$5-20 per run, depends on scenario)
- **Duration**: 15-45 minutes
- **Examples**:
  - Minimal deployment
  - EFS-enabled deployment
  - ECR-enabled deployment

```bash
go test -v -run "TestScenario(Minimal|EFS|ECR)" -timeout 45m
```

### 3. Expensive Tests (Slow, Costly)

- **Purpose**: Test complex scenarios with NAT, private networking
- **Cost**: High (~$10-30 per run)
- **Duration**: 30-60 minutes
- **Examples**:
  - Private networking (requires NAT gateway)
  - Full-featured (NAT + EFS + ECR)

```bash
# Skip by default with -short flag
go test -v -short ./...

# Run explicitly
go test -v -run "TestScenario(Private|Full)" -timeout 60m
```

## Writing Tests

### Basic Test Structure

```go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestMyModule(t *testing.T) {
    t.Parallel()  // Run in parallel with other tests

    stackName := GetRandomStackName("test-prefix")

    terraformOptions := &terraform.Options{
        TerraformDir: "./fixtures/my-module",
        Vars: map[string]interface{}{
            "stack_name": stackName,
        },
        NoColor: true,
    }

    // Always clean up
    defer terraform.Destroy(t, terraformOptions)

    // Deploy
    terraform.InitAndApply(t, terraformOptions)

    // Validate
    output := terraform.Output(t, terraformOptions, "my_output")
    assert.NotEmpty(t, output)
}
```

### Using Terragrunt in Tests

```go
func TestWithTerragrunt(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir:    "./live/scenarios/my-scenario",
        TerraformBinary: "terragrunt",  // Use terragrunt instead
        NoColor:         true,
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    // Validations...
}
```

### Skipping Expensive Tests

```go
func TestExpensive(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping expensive test in short mode")
    }
    
    // Test implementation...
}
```

### Using Helper Functions

```go
// Get unique stack name
stackName := GetRandomStackName("test")

// Get test ID (timestamp)
testID := GetTestID()

// Get environment variable with fallback
license := GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-key")

// Get required environment variable (fails test if missing)
org := GetRequiredEnv(t, "GITHUB_ORG", "")
```

## CI/CD Integration

### GitHub Actions

Tests run automatically on:
- Pull requests
- Pushes to main branch
- Manual workflow dispatch

See `.github/workflows/terratest.yml` for configuration.

### Environment Variables in CI

Required secrets in GitHub Actions:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `RUNS_ON_LICENSE_KEY`
- `TEST_GITHUB_ORG`

### Test Matrix

CI runs tests in parallel using matrix strategy:
- Unit tests: Run in parallel per module
- Scenario tests: Run in parallel per scenario
- Integration tests: Run sequentially

## Troubleshooting

### Tests Fail with "command not found: terragrunt"

**Solution**: Install Terragrunt
```bash
brew install terragrunt
```

### Tests Fail with AWS Credentials Error

**Solution**: Configure AWS credentials
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
```

### Tests Time Out

**Solution**: Increase timeout
```bash
go test -v -timeout 120m ./...
```

### Resources Not Cleaned Up

**Solution**: Manually destroy Terraform resources
```bash
cd test/fixtures/storage  # or test/live/scenarios/minimal
terraform destroy
# or
terragrunt destroy
```

### "Resource Already Exists" Error

**Solution**: Use unique stack names (automatically handled by helpers)
```go
stackName := GetRandomStackName("test")  // Generates unique name
```

### NAT Gateway Costs Too High

**Solution**: Skip expensive tests
```bash
go test -v -short ./...  # Skips tests with NAT
```

### Go Module Dependency Issues

**Solution**: Update dependencies
```bash
cd test
go mod tidy
go mod download
```

## Cost Management

### Estimated Test Costs

| Test Type | Duration | Cost | Notes |
|-----------|----------|------|-------|
| Unit (storage) | 5-10 min | $0.50-1 | S3 only |
| Unit (optional) | 5-10 min | $0.50-1 | ECR only |
| Scenario (minimal) | 15-20 min | $2-5 | App Runner + S3 |
| Scenario (EFS) | 20-30 min | $3-7 | + EFS |
| Scenario (ECR) | 15-20 min | $2-5 | + ECR |
| Scenario (private) | 30-45 min | $10-15 | + NAT gateway |
| Scenario (full) | 45-60 min | $15-25 | NAT + EFS + ECR |

### Cost Optimization Tips

1. **Use `-short` flag** to skip expensive tests during development
2. **Run expensive tests in CI only**, not locally
3. **Clean up promptly** - use `defer terraform.Destroy()`
4. **Monitor AWS costs** in Cost Explorer
5. **Set billing alerts** in AWS
6. **Use dedicated test account** to isolate costs

## Test Development Workflow

1. **Write test** in appropriate `*_test.go` file
2. **Create/update fixture** in `fixtures/` or `live/scenarios/`
3. **Run test locally**:
   ```bash
   go test -v -run TestMyNew -timeout 30m
   ```
4. **Verify cleanup**:
   ```bash
   # Check no resources left
   terraform show  # Should be empty
   ```
5. **Commit** and let CI run full test suite

## Best Practices

1. **Always use `t.Parallel()`** for independent tests
2. **Always use `defer terraform.Destroy()`** for cleanup
3. **Use unique names** with `GetRandomStackName()`
4. **Tag resources** for easy identification
5. **Skip expensive tests** with `if testing.Short()`
6. **Validate outputs** before checking AWS resources
7. **Use meaningful test names** that describe what's being tested
8. **Document** why tests are skipped

## Getting Help

- **Issues**: Report at https://github.com/sjysngh/runs-on-tf/issues
- **Terratest Docs**: https://terratest.gruntwork.io/docs/
- **Terragrunt Docs**: https://terragrunt.gruntwork.io/docs/

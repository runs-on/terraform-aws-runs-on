# RunsOn Terraform Module Tests

This directory contains the test suite for the RunsOn Terraform module using [Terratest](https://terratest.gruntwork.io/).

## Overview

The tests deploy **real AWS infrastructure** to validate the module's functionality, security, and compliance. Tests are written in Go and use the AWS SDK v2 for validations.

## Prerequisites

### Required Tools

- Go 1.26+
- OpenTofu 1.9+ (or Terraform 1.6+)
- AWS CLI v2

Install all tools automatically using [mise](https://mise.jdx.dev/):

```bash
cd test
mise install
```

### AWS Credentials

Tests require AWS credentials with permissions to create:

- VPCs, subnets, NAT gateways
- S3 buckets
- IAM roles and policies
- EC2 instances and launch templates
- App Runner services
- CloudWatch log groups
- DynamoDB tables
- SQS queues
- (Optional) EFS file systems
- (Optional) ECR repositories

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RUNS_ON_LICENSE_KEY` | Yes | - | RunsOn license key |
| `AWS_REGION` | No | `us-east-1` | AWS region for deployments |
| `RUNS_ON_TEST_REPO` | No | - | GitHub repo for integration tests (`owner/repo` format) |
| `RUNS_ON_TEST_WORKFLOW` | No | - | Workflow file name for integration tests (e.g., `test.yml`) |
| `GITHUB_TOKEN` | No | - | GitHub token for integration tests |
| `RUNS_ON_APP_IMAGE` | No | - | Override App Runner image |
| `RUNS_ON_APP_TAG` | No | - | Override App Runner image tag |

The `github_organization` module variable is automatically extracted from `RUNS_ON_TEST_REPO` (e.g., `my-org/my-repo` → `my-org`). For infrastructure-only tests, it defaults to `test-org`.

Integration tests require all three: `RUNS_ON_TEST_REPO`, `RUNS_ON_TEST_WORKFLOW`, and `GITHUB_TOKEN`.

## Running Tests Locally

### Minimal Setup (Infrastructure Tests Only)

Run the basic scenario with just a license key:

```bash
cd test
export RUNS_ON_LICENSE_KEY="your-license-key"

go test -v -timeout 45m -run "TestScenarioBasic" ./...
```

This runs all infrastructure validations:

- S3 bucket encryption, logging, public access blocking
- IAM role permissions
- S3 versioning and log retention
- App Runner health checks
- EC2 functional tests (S3 access, CloudWatch logging)

Integration tests that require GitHub are **automatically skipped**.

### With Integration Tests (Observer Mode)

To run the full integration test that validates a GitHub Actions workflow executes on a RunsOn runner:

```bash
export RUNS_ON_LICENSE_KEY="your-license-key"
export GITHUB_TOKEN="ghp_xxxx"
export RUNS_ON_TEST_REPO="my-org/my-test-repo"
export RUNS_ON_TEST_WORKFLOW="my-workflow.yml"

go test -v -timeout 45m -run "TestScenarioBasic" ./...
```

The integration test runs in **observer mode**:

1. Test deploys infrastructure and displays the App Runner URL
2. You manually register the RunsOn app at the displayed URL
3. You manually trigger the specified workflow
4. Test detects and monitors the workflow run
5. Test validates the runner was launched and job completed

To abort the observer mode gracefully, create the abort file shown in the test output:

```bash
touch /tmp/runson-<test-id>-abort
```

### Testing a Different App Version

To test a specific RunsOn app version, override the App Runner image and tag:

```bash
export RUNS_ON_LICENSE_KEY="your-license-key"
export RUNS_ON_APP_IMAGE="public.ecr.aws/c5h5o9k1/runs-on/runs-on:v2.11.0"
export RUNS_ON_APP_TAG="v2.11.0"

go test -v -timeout 45m -run "TestScenarioBasic" ./...
```

This is useful for:
- Testing pre-release versions before upgrading
- Validating custom builds or forks
- Regression testing against older versions

### Full-Featured Scenario

Test all optional features (NAT gateway, EFS, ECR):

```bash
export RUNS_ON_LICENSE_KEY="your-license-key"

go test -v -timeout 60m -run "TestScenarioFullFeatured" ./...
```

This scenario:

- Deploys NAT gateway for private networking
- Tests EFS mount, read, write operations from EC2
- Tests ECR Docker Buildx cache push/pull
- Validates private subnet instances have no public IP
- Validates outbound connectivity via NAT

### Skip Expensive Tests

Use `-short` to skip tests requiring NAT gateway:

```bash
go test -v -short ./...
```

### Run All Tests

```bash
go test -v -timeout 90m ./...
```

## Test Scenarios

### TestScenarioBasic

Deploys a minimal RunsOn stack and validates:

| Category | Validations |
|----------|-------------|
| Outputs | Stack name, App Runner URL, bucket names, IAM role |
| Security | S3 encryption (KMS), access logging, public access blocking, IAM permissions |
| Compliance | S3 versioning, CloudWatch log retention |
| Functional | App Runner health, S3 access from EC2, CloudWatch logging |
| Integration | (Optional) GitHub workflow execution |

**Duration**: 30-45 minutes  
**Cost**: ~$1-2 per run

### TestScenarioFullFeatured

Deploys a full RunsOn stack with all features:

| Category | Validations |
|----------|-------------|
| All Basic | Everything from TestScenarioBasic |
| Private Networking | No public IP on instances, NAT gateway connectivity |
| EFS | Mount, write, read, unmount operations |
| ECR | Docker Buildx cache-to and cache-from |

**Duration**: 45-60 minutes  
**Cost**: ~$3-5 per run

## Test Architecture

```
test/
├── scenarios_test.go   # Main test scenarios
├── helpers.go          # AWS SDK helpers and validators
├── go.mod              # Go module dependencies
├── mise.toml           # Tool versions
└── fixtures/
    └── vpc/            # VPC fixture module
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Test Flow

1. Deploy VPC fixture (public/private subnets, optional NAT)
2. Deploy runs-on root module
3. Run validation suites
4. Cleanup (terraform destroy)

All cleanup runs via `defer`, so infrastructure is destroyed even if tests fail.

## Validation Functions

### Security

| Function | Description |
|----------|-------------|
| `ValidateS3BucketEncryption` | Verifies KMS encryption enabled |
| `ValidateS3BucketLogging` | Verifies access logging to logging bucket |
| `ValidateS3BucketPublicAccessBlocked` | Verifies all public access settings blocked |
| `ValidateIAMRoleNotOverlyPermissive` | Verifies no admin/power user policies attached |

### Compliance

| Function | Description |
|----------|-------------|
| `ValidateS3BucketVersioning` | Verifies versioning status matches expected |
| `ValidateCloudWatchLogRetention` | Verifies retention policy is set (not infinite) |

### Functional

| Function | Description |
|----------|-------------|
| `ValidateAppRunnerHealth` | HTTP health check on `/ping` endpoint |
| `ValidateS3AccessFromEC2` | Tests IAM policy allows/denies correct S3 paths |
| `ValidateEC2CloudWatchLogs` | Verifies log group exists and is configured |
| `ValidateEFSMountFromEC2` | Tests EFS mount, write, read, verify, unmount |
| `ValidateECRPushPullFromEC2` | Tests Docker Buildx with ECR registry cache |
| `ValidatePrivateNetworkConnectivity` | Tests outbound HTTPS via NAT gateway |
| `ValidateInstanceHasNoPublicIP` | Verifies private subnet isolation |

### Integration

| Function | Description |
|----------|-------------|
| `WatchForWorkflowRun` | Polls GitHub API for workflow_dispatch runs |
| `MonitorWorkflowJobStates` | Detects stuck jobs (no runner available) |
| `WaitForWorkflowCompletion` | Waits for workflow to complete |
| `ValidateRunnerLaunched` | Verifies EC2 runner instance was created |

### Running a Single Subtest

```bash
go test -v -timeout 45m -run "TestScenarioBasic/Security" ./...
go test -v -timeout 45m -run "TestScenarioBasic/Functional/S3Access" ./...
```

## Cost Considerations

Tests deploy real AWS resources:

| Component | Cost | Notes |
|-----------|------|-------|
| NAT Gateway | ~$0.045/hr + data | Most expensive, use `-short` to skip |
| App Runner | ~$0.007/hr (idle) | Scales to zero when not in use |
| EC2 (t3.micro) | ~$0.0104/hr | Used for functional tests |
| S3 | Minimal | A few cents for test objects |
| EFS | ~$0.30/GB-month | Only provisioned storage used |
| ECR | ~$0.10/GB-month | Only test images |

**Tip**: Run `TestScenarioBasic` during development. Only run `TestScenarioFullFeatured` before merging.

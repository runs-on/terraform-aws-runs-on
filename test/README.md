# RunsOn Terraform Module Tests

This directory contains the test suite for the RunsOn Terraform module using [Terratest](https://terratest.gruntwork.io/).

## Overview

The tests deploy **real AWS infrastructure** to validate the module's functionality, security, and compliance. Tests are written in Go and use the AWS SDK v2 for validations.

## Prerequisites

### Required Tools

- Go 1.26+
- OpenTofu 1.9+ (or Terraform 1.57+)
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
- Secrets Manager secrets
- (Optional) EFS file systems
- (Optional) ECR repositories

## Environment Variables

### Infrastructure Tests

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RUNS_ON_LICENSE_KEY` | Yes | - | RunsOn license key |
| `AWS_REGION` | No | `us-east-1` | AWS region for deployments |
| `GITHUB_ORG` | No | `test-org` | Override GitHub organization name |
| `RUNS_ON_APP_IMAGE` | No | - | Override App Runner image |
| `RUNS_ON_APP_TAG` | No | - | Override App Runner image tag |

The `github_organization` module variable is automatically extracted from `RUNS_ON_TEST_REPO` (e.g., `my-org/my-repo` → `my-org`), then falls back to `GITHUB_ORG`, then defaults to `test-org`.

### E2E Tests

These additional variables are required for `TestE2E`. Authentication uses a GitHub App installation token — no separate PAT is needed.

| Variable | Required | Description |
|----------|----------|-------------|
| `RUNS_ON_TEST_REPO` | Yes | Repository in `owner/repo` format |
| `RUNS_ON_TEST_WORKFLOW` | Yes | Workflow file name (e.g., `test.yml`) |
| `GITHUB_APP_ID` | Yes | GitHub App ID (numeric) |
| `GITHUB_APP_PRIVATE_KEY` | Yes | GitHub App private key (PEM format) |
| `GITHUB_APP_WEBHOOK_SECRET` | Yes | GitHub App webhook secret |
| `GITHUB_APP_CLIENT_ID` | Yes | GitHub App OAuth client ID |
| `GITHUB_APP_CLIENT_SECRET` | Yes | GitHub App OAuth client secret |

Optional feature flags for E2E tests:

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_EFS` | `false` | Set to `true` to deploy EFS |
| `ENABLE_ECR` | `false` | Set to `true` to deploy ECR |
| `PRIVATE_MODE` | `false` | Private networking mode: `true`, `always`, or `only` (auto-enables NAT) |

`PRIVATE_MODE` maps directly to the Terraform `private_mode` variable:

| Value | Meaning |
|-------|---------|
| `false` | Disabled — runners use public subnets (default) |
| `true` | Opt-in — runners use public by default, private via workflow label |
| `always` | Default private — runners use private by default, public via opt-out label |
| `only` | Forced private — all runners must use private subnets |

## Running Tests Locally

### Plan Tests (No AWS Resources)

Run plan-only validation — no infrastructure is created:

```bash
cd test
go test -v -timeout 15m -run "TestPlan" ./...
```

These tests validate that feature flags control which resources appear in the plan output (EFS, ECR, VPC connector, security groups).

### Basic Scenario (Infrastructure Tests)

Run the basic scenario with just a license key:

```bash
cd test
export RUNS_ON_LICENSE_KEY="your-license-key"

go test -v -timeout 45m -run "TestScenarioBasic" ./...
```

This deploys infrastructure and runs all validations:

- S3 bucket encryption, logging, public access blocking
- IAM role permissions
- S3 versioning and log retention
- Secrets Manager wiring (StackConfig)
- Resource tagging discovery
- App Runner health checks
- EC2 functional tests (S3 access, CloudWatch logging)

### Full-Featured Scenario

Test all optional features (NAT gateway, EFS, ECR):

```bash
export RUNS_ON_LICENSE_KEY="your-license-key"

go test -v -timeout 90m -run "TestScenarioFullFeatured" ./...
```

This scenario additionally:

- Deploys NAT gateway for private networking
- Tests EFS mount, read, write operations from EC2
- Tests ECR Docker Buildx cache push/pull
- Validates private subnet instances have no public IP
- Validates outbound connectivity via NAT

### Private Networking Scenario

Test deployment with private networking enabled:

```bash
export RUNS_ON_LICENSE_KEY="your-license-key"

go test -v -timeout 60m -run "TestScenarioPrivateNetworking" ./...
```

Runs the same validations as Basic, plus private subnet isolation and NAT gateway connectivity.

### End-to-End Test

Run the fully automated E2E test that deploys infrastructure, wires up a GitHub App, dispatches a workflow, and verifies a runner processes the job:

```bash
export RUNS_ON_LICENSE_KEY="your-license-key"
export RUNS_ON_TEST_REPO="my-org/my-test-repo"
export RUNS_ON_TEST_WORKFLOW="test.yml"
export GITHUB_APP_ID="123456"
export GITHUB_APP_PRIVATE_KEY="$(cat key.pem)"
export GITHUB_APP_WEBHOOK_SECRET="your-webhook-secret"
export GITHUB_APP_CLIENT_ID="Iv1.xxxx"
export GITHUB_APP_CLIENT_SECRET="xxxx"

go test -v -timeout 60m -run "TestE2E" ./...
```

This test can also be triggered via the `E2E Test` GitHub Actions workflow (`e2e.yml`) with configurable scenario inputs (EFS, ECR, private mode).

The test flow:

1. Deploys infrastructure with GitHub App credentials injected via Terraform variables
2. Waits for App Runner health check
3. Updates the GitHub App webhook URL to point to the new deployment
4. Dispatches the specified workflow via GitHub API
5. Monitors for the workflow run to start (5 min timeout)
6. Monitors job state transitions — detects if jobs are stuck in queue (5 min timeout)
7. Waits for workflow completion (10 min timeout)
8. Validates a runner EC2 instance was launched
9. Extracts boot timing metrics from job logs
10. Destroys all infrastructure

### Testing a Different App Version

Override the App Runner image and tag:

```bash
export RUNS_ON_LICENSE_KEY="your-license-key"
export RUNS_ON_APP_IMAGE="public.ecr.aws/c5h5o9k1/runs-on/runs-on:v2.11.0"
export RUNS_ON_APP_TAG="v2.11.0"

go test -v -timeout 45m -run "TestScenarioBasic" ./...
```

### Skip Expensive Tests

Use `-short` to skip tests requiring NAT gateway:

```bash
go test -v -short ./...
```

### Run All Tests

```bash
go test -v -timeout 120m ./...
```

## Test Scenarios

### TestPlanConditionalResources / TestPlanResourceCounts

Validates that feature flags control which resources appear in the plan output. Runs `tofu plan` with dummy values — **no AWS resources are created**.

| Sub-case | What it checks |
|----------|---------------|
| BaselineNoOptional | EFS, ECR, VPC connector absent |
| EFSOnly | EFS resources present, ECR absent |
| ECROnly | ECR resources present, EFS absent |
| PrivateModeTrue | VPC connector present |
| PrivateModeWithDelay | `time_sleep` resource present |
| AllFeatures | EFS, ECR, VPC connector all present |
| SGCreatedWhenEmpty | Security group created when none provided |
| SGNotCreatedWhenProvided | Security group not created when provided |
| ResourceCounts | Baseline plan creates ≥30 resources |

**Duration**: 2-5 minutes | **Cost**: Free

### TestScenarioBasic

Deploys a minimal RunsOn stack and validates:

| Category | Validations |
|----------|-------------|
| Outputs | Stack name, App Runner URL, bucket names, IAM role |
| Security | S3 encryption (KMS), access logging, public access blocking, IAM permissions |
| Compliance | S3 versioning, CloudWatch log retention |
| Wiring | StackConfig Secrets Manager secret matches Terraform outputs |
| Tagging | `runs-on-stack-name` tag on ≥5 resources |
| Advanced | App Runner health check |
| Functional | S3 access from EC2 (allowed/denied paths), CloudWatch logging |

**Duration**: 30-45 minutes | **Cost**: ~$1-2

### TestScenarioPrivateNetworking

Deploys with private networking (`private_mode = "true"` + NAT gateway):

| Category | Validations |
|----------|-------------|
| All Basic | Everything from TestScenarioBasic |
| Private | No public IP on instances, NAT gateway connectivity |

**Duration**: 35-50 minutes | **Cost**: ~$2-3

### TestScenarioFullFeatured

Deploys with all features enabled (NAT + EFS + ECR):

| Category | Validations |
|----------|-------------|
| All Basic | Everything from TestScenarioBasic |
| Private Networking | No public IP on instances, NAT gateway connectivity |
| EFS | Mount, write, read, verify, unmount from EC2 |
| ECR | Docker Buildx `cache-to` and `cache-from` with ECR registry |

**Duration**: 45-60 minutes | **Cost**: ~$3-5

### TestE2E

Fully automated E2E test with a real GitHub Actions workflow:

| Step | What happens |
|------|-------------|
| Deploy | Infrastructure with GitHub App credentials |
| Health | App Runner `/ping` health check |
| Webhook | Updates GitHub App webhook URL to new deployment |
| Dispatch | Triggers `workflow_dispatch` on test repo |
| Monitor | Watches for run start, job state transitions, completion |
| Validate | Runner EC2 instance was launched, boot timings extracted |

**Duration**: 30-45 minutes | **Cost**: ~$1-2

## Test Architecture

```
test/
├── scenarios_test.go    # Infrastructure test scenarios (Basic, FullFeatured, PrivateNetworking)
├── e2e_test.go          # End-to-end test with GitHub Actions
├── plan_test.go         # Plan-only validation tests (no AWS resources)
├── helpers.go           # Scenario harness, config types, AWS/GitHub helpers
├── validators.go        # Composable validation functions (security, compliance, wiring, tagging, functional)
├── go.mod               # Go module dependencies
├── go.sum
├── mise.toml            # Tool versions
└── fixtures/
    └── vpc/             # VPC fixture module
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Test Flow

1. Deploy VPC fixture (public/private subnets, optional NAT)
2. Deploy runs-on root module
3. Run validation suites (composable per scenario)
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

### Wiring

| Function | Description |
|----------|-------------|
| `ValidateStackConfig` | Verifies Secrets Manager config JSON matches Terraform outputs (buckets, IAM roles, launch templates, SQS queues, DynamoDB tables, SNS topic) |

### Tagging

| Function | Description |
|----------|-------------|
| `ValidateResourceTagging` | Discovers resources tagged with `runs-on-stack-name` and verifies ≥5 exist |

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

### E2E

| Function | Description |
|----------|-------------|
| `UpdateGitHubAppWebhookURL` | Updates GitHub App webhook via JWT |
| `WatchForWorkflowRun` | Polls GitHub API for `workflow_dispatch` runs |
| `MonitorWorkflowJobStates` | Detects stuck jobs (no runner available) |
| `WaitForWorkflowCompletion` | Waits for workflow to complete |
| `ValidateRunnerLaunched` | Verifies EC2 runner instance was created |
| `FetchJobLogs` | Downloads raw logs for all jobs in a run |
| `ParseBootTimings` | Extracts timing metrics from runner logs |

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

**Tip**: Run `TestPlanConditionalResources` during development (free). Run `TestScenarioBasic` before merging. Only run `TestScenarioFullFeatured` for releases or major changes.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform/OpenTofu module for deploying [RunsOn](https://runs-on.com/) self-hosted GitHub Actions runner infrastructure on AWS. It provides feature parity with the official RunsOn CloudFormation stack.

## Build and Test Commands

```bash
# Initialize OpenTofu
tofu init

# Validate configuration
tofu validate

# Plan changes
tofu plan

# Apply changes
tofu apply

# Run all tests (requires AWS credentials and deploys real infrastructure)
cd test && go test -v -timeout 60m ./...

# Run a single test
cd test && go test -v -timeout 30m -run TestStorageModuleBucketCreation ./...

# Run tests excluding expensive ones (NAT gateway, EFS)
cd test && go test -v -short -timeout 30m ./...

# Run scenario tests with Terragrunt
cd test && go test -v -timeout 45m -run TestScenarioBasic ./...
```

## Architecture

### Module Structure

- **Root module** (`main.tf`): Orchestrates all submodules and creates a mock CloudFormation stack for App Runner compatibility
- **modules/storage**: S3 buckets (config, cache, logging) with lifecycle policies and encryption
- **modules/compute**: EC2 launch templates (Linux/Windows, default/private), IAM roles, instance profiles, CloudWatch log groups
- **modules/core**: App Runner service, SQS queues (7 queues), DynamoDB tables, EventBridge rules, SNS topics
- **modules/optional**: EFS file system and ECR repository (feature-flagged with `enable_efs` and `enable_ecr`)

### Key Dependencies Between Modules

```
storage ──────────────────────────────────┐
                                          ├──> core (App Runner, SQS, DynamoDB)
compute (launch templates, IAM roles) ────┘

optional (EFS, ECR) ──> compute (userdata references)
```

### Test Structure

- **test/fixtures/**: Isolated module tests for storage and compute
- **test/live/**: Terragrunt-based scenario tests
  - `_shared/vpc/`: Shared VPC dependency
  - `scenarios/`: Test scenarios (basic, private-networking, efs-enabled, ecr-enabled, full-featured)
- Uses Terratest with Terragrunt for integration testing

### Environment Variables for Tests

```bash
TEST_ID=<timestamp>           # Auto-generated unique ID
GITHUB_ORG=<organization>     # GitHub organization (default: test-org)
RUNS_ON_LICENSE_KEY=<key>     # RunsOn license key
ENABLE_NAT=true               # Enable NAT gateway for private networking tests
AWS_REGION=us-east-1          # AWS region (default)
```

## Key Implementation Details

- Requires OpenTofu >= 1.6.0 or Terraform with AWS provider >= 5.0
- Security groups: If `security_group_ids` is empty, the module creates security groups automatically (see `security_groups.tf`)
- Private networking modes: `false`, `true`, `always`, `only` - controls whether runners use private subnets
- The mock CloudFormation stack (`aws_cloudformation_stack.runs_on_mock`) exists for App Runner environment variable compatibility

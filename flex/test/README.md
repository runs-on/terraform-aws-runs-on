# Terraform Test Suite

This package validates the Terraform deployment shape used by RunsOn.

## Test Pyramid

The Terraform test stack is intentionally split into four layers:

1. Static validation in CI: `tofu fmt`, `tofu validate`, `tflint`, and generated-doc checks.
2. Plan-only structured tests: fast `tofu plan` coverage against isolated temp copies of the Terraform tree.
3. Apply-based smoke scenarios: real AWS deploy/validate/destroy runs for the basic, private, and full configurations.
4. End-to-end GitHub integration: a full ephemeral deployment that updates a GitHub App webhook, dispatches a workflow, and confirms a runner processes it.

## What It Covers

- Terraform outputs and wiring
- ECS worker service health and task-definition wiring
- public ingress setup availability checks for the default interactive flow and `/readyz` readiness checks for declaratively configured GitHub App scenarios
- stack config secret contents and version pinning
- storage, IAM, networking, and runner launch behavior

## Important Assumptions

- The worker task must pin `RUNS_ON_STACK_CONFIG_SECRET_ARN` and `RUNS_ON_STACK_CONFIG_SECRET_VERSION`.
- The pinned stack config secret must already include `IngressURL` and `ServiceLogGroupName`.
- Live service status is derived from ECS, not from values embedded in the secret.

## Environment

Plan-only tests are expected to be fast and deterministic because each test runs against its own temp-copied Terraform tree and inspects structured `terraform show -json` output instead of CLI text. They still need AWS credentials because the root module resolves caller identity and region through AWS data sources during planning.

Apply-based smoke scenarios and the end-to-end GitHub integration test need AWS credentials and the scenario environment variables described in the test harness. Those runs are intentionally serialized because they are long-lived, quota-sensitive, and operate against real cloud resources.

## CI Integration

The monorepo `Terraform / Test` workflow runs the integration path with `make -C terraform test-integration-ci-image` on trusted same-repo pushes, trusted same-repo pull requests, and manual `workflow_dispatch` runs. That root `terraform/Makefile` target delegates to the Flex test module under `terraform/flex/test/`.

That CI job exports these required environment variables into the Terratest process:

- `RUNS_ON_LICENSE_KEY`
- `RUNS_ON_TEST_REPO`
- `RUNS_ON_TEST_WORKFLOW`
- `RUNS_ON_TEST_WORKFLOW_REF` (optional, defaults to `main`)
- `RUNS_ON_TEST_WORKFLOW_INPUTS` (optional JSON object)
- `GITHUB_APP_ID`
- `GITHUB_APP_PRIVATE_KEY`
- `GITHUB_APP_WEBHOOK_SECRET`
- `GITHUB_APP_CLIENT_ID`
- `GITHUB_APP_CLIENT_SECRET`
- `GITHUB_TOKEN` (optional, preferred for GitHub Actions API access in CI)

`RUNS_ON_TEST_REPO` points at this repository. In CI we dispatch `.github/workflows/terraform-integration-runner.yml` from the current branch so the workflow definition stays in sync with any integration-harness changes in the same branch while still exercising a single RunsOn-managed job end to end. `RUNS_ON_TEST_WORKFLOW_REF` and `RUNS_ON_TEST_WORKFLOW_INPUTS` let callers override the dispatch target when they need a different workflow or inputs. When `GITHUB_TOKEN` is available, the harness prefers it for workflow dispatch, run polling, and log downloads because GitHub App installation tokens can have different Actions API access.

The repository that runs `Terraform / Test` therefore needs these GitHub Actions settings configured:

- `RUNS_ON_LICENSE_KEY`
- `AWS_CI_ROLE_ARN`
- repo variable `GH_APP_ID`
- secret `GH_APP_PRIVATE_KEY`
- secret `GH_APP_WEBHOOK_SECRET`
- secret `GH_APP_CLIENT_ID`
- secret `GH_APP_CLIENT_SECRET`

The integration job serializes execution with a dedicated concurrency group because it temporarily updates the GitHub App webhook URL to point at the ephemeral test stack ingress.

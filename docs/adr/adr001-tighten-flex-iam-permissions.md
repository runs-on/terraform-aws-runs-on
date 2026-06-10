---
id: adrs-adr001
title: 'ADR001: Tighten Flex IAM Permissions'
# prettier-ignore
description: Architecture Decision Record (ADR) for tightening RunsOn Flex IAM permissions to least-privilege scopes
---

## Context

RunsOn Flex provisions an AWS-hosted control plane and ephemeral EC2 runners for GitHub Actions workloads. The Terraform module creates known AWS resources for this deployment path, including SSM parameters, Secrets Manager secrets, SQS queues, DynamoDB tables and indexes, CloudWatch log groups, Lambda functions, API Gateway routes, S3 cache prefixes, EC2 launch infrastructure, EFS file systems, and runner instance roles.

Several IAM statements historically used broader resource scopes than the Flex deployment requires. Some statements grouped AWS APIs that require `Resource = "*"` with APIs that support resource-level permissions. Other statements used managed policies, wildcard resource patterns, or resource collections where Terraform already knows the exact target resources.

The Flex module also needs to preserve operational behavior for existing deployments. Some AWS APIs do not support resource-level constraints, and runner scheduling remains dynamic across instance types, launch templates, AMIs, subnets, and optional features. Least-privilege changes therefore need to reduce blast radius without constraining documented Flex behavior.

The shared `control_plane/runtime` module is consumed by both the Flex and Fleet control planes, so changes to its task-role statements affect both deployment paths. Two AWS authorization behaviors constrain how its launch permissions can be narrowed: spot launches authorize `ec2:RunInstances` (and tag-on-create `ec2:CreateTags`) against the `spot-instances-request` resource type, and the worker verifies the EC2 Spot service-linked role with `iam:GetRole` before calling `iam:CreateServiceLinkedRole`.

This decision has a local constraint: the module should not shift Terraform-managed resource discovery or policy wiring onto users by requiring them to hard-code values that the module already manages.

## Decision

We will scope Flex IAM permissions to Terraform-managed resources whenever AWS supports resource-level authorization and the target resource is known.

We will keep AWS-required wildcard resource permissions only where the AWS service authorization model requires `Resource = "*"`, and we will use service-specific conditions where practical, such as CloudWatch metric namespaces.

We will scope the Flex worker role to the license-status SSM parameter instead of all stack parameters, and we will remove worker SSM delete permissions.

We will grant the Flex worker access to active SQS queues only. Dead-letter queues will remain part of SQS redrive configuration rather than normal worker consume or mutate permissions.

We will enumerate known DynamoDB workflow-job indexes instead of granting access to all indexes on the table.

We will replace broad Lambda basic-execution managed policy attachments for Terraform-managed Flex Lambda log groups with inline policies limited to `logs:CreateLogStream` and `logs:PutLogEvents` on those log groups.

We will scope API Gateway Lambda invoke permissions to the expected webhook and admin routes.

We will narrow shared runtime permissions for runner-role lookup, EC2 launch resource types, EC2 cleanup resources, and S3 cache prefixes. The enumerated launch resource types will include `spot-instances-request` so that spot launches remain authorized once the account-wide EC2 resource wildcard is removed.

We will scope the worker's standalone `iam:GetRole` to the EC2 Spot service-linked role, which the worker reads before creating it. `iam:GetRole` on the runner instance role remains granted alongside `iam:PassRole` in the existing runner-role statement.

We will reduce runner instance permissions by using read-only ECR Public access, removing CloudWatch log-group management permissions, scoping self-tagging to the source instance, and scoping EFS client mount, write, and mount-target describe permissions to the configured file system.

We will add policy-shape tests that assert these least-privilege boundaries so future changes do not unintentionally reintroduce broad grants. Because OpenTofu releases before 1.10 do not short-circuit `&&`, assertions that inspect heterogeneous IAM statements will wrap shape-dependent lookups in `try(...)` so the suites pass across supported OpenTofu versions.

## Consequences

The Flex control plane and runner roles have a smaller IAM blast radius while continuing to support the documented Flex deployment model. Because the runtime module is shared, the Fleet control plane task role receives the same narrowed launch, lookup, cleanup, and cache permissions.

The module remains compatible with AWS APIs that require wildcard resources because those wildcards are retained where needed.

Terraform-managed Lambda functions no longer depend on broad AWS-managed log policies when their log groups are already managed by the module.

The worker can no longer delete SSM parameters or process dead-letter queues through its normal runtime role. This change does not add a replacement mechanism for worker-initiated DLQ replay or SSM cleanup. Operators who need those workflows must use separate explicit permissions until the module provides a narrowly scoped feature for them.

Future DynamoDB index additions for workflow jobs must update IAM policy resources and policy-shape tests.

Future S3 cache prefix additions must update runtime task policy resources and policy-shape tests.

Future use of additional EC2 launch resource types — for example targeted capacity reservations or placement groups — must add those resource-type ARNs to the enumerated launch statement, since the account-wide EC2 wildcard no longer covers them. Until then, Flex operators who need extra launch permissions can attach them through the existing `app_custom_policy_arn` variable, which adds an operator-managed policy to the worker task role without modifying the module.

The test suite now contains more explicit assertions about IAM policy shape, increasing maintenance cost when legitimate permissions change.

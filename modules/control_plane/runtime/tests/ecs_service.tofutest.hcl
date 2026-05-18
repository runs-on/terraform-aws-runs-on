mock_provider "aws" {
  mock_data "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-stack-runtime"
    }
  }
}

variables {
  region                   = "us-east-1"
  account_id               = "123456789012"
  stack_name               = "test-stack"
  cluster_name             = "test-stack-runtime"
  service_name             = "runs-on"
  task_definition_family   = "test-stack-runtime"
  execution_role_name      = "test-stack-runtime-execution"
  task_role_name           = "test-stack-runtime-task"
  task_policy_name         = "test-stack-runtime-task-policy"
  runner_instance_role_arn = "arn:aws:iam::123456789012:role/test-stack-runner"
  cache_bucket_arn         = "arn:aws:s3:::test-stack-cache"
  log_group_name           = "/runs-on/test-stack/runtime"
  log_retention_days       = 7
  cpu                      = 512
  memory                   = 1024
  desired_count            = 1
  assign_public_ip         = false
  security_group_ids       = ["sg-12345678"]
  subnet_ids               = ["subnet-12345678", "subnet-87654321"]
  tags = {
    Environment        = "test"
    "runs-on-stack-id" = "test-stack"
  }

  container_definitions = [
    {
      name      = "runs-on"
      image     = "example.com/runs-on:latest"
      essential = true
    }
  ]
}

run "defaults_to_fargate_capacity_provider" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.this.capacity_provider_strategy) == 1
    error_message = "runtime ECS service should have exactly one capacity provider strategy."
  }

  assert {
    condition     = one(aws_ecs_service.this.capacity_provider_strategy).capacity_provider == "FARGATE"
    error_message = "runtime ECS service should default to the FARGATE capacity provider."
  }

  assert {
    condition     = one(aws_ecs_service.this.capacity_provider_strategy).weight == 1
    error_message = "runtime ECS service capacity provider strategy should have weight 1."
  }
}

run "defaults_force_new_deployment_false" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.force_new_deployment == false
    error_message = "runtime ECS service should not force new deployments by default."
  }
}

run "can_force_new_deployment" {
  command = plan

  variables {
    force_new_deployment = true
  }

  assert {
    condition     = aws_ecs_service.this.force_new_deployment == true
    error_message = "runtime ECS service should enable forced deployments when requested."
  }
}

run "can_use_fargate_spot_capacity_provider" {
  command = plan

  variables {
    capacity_provider = "FARGATE_SPOT"
  }

  assert {
    condition     = one(aws_ecs_service.this.capacity_provider_strategy).capacity_provider == "FARGATE_SPOT"
    error_message = "runtime ECS service should use the requested FARGATE_SPOT capacity provider."
  }
}

run "rejects_invalid_capacity_provider" {
  command = plan

  variables {
    capacity_provider = "SPOT"
  }

  expect_failures = [
    var.capacity_provider,
  ]
}

run "propagates_tags_and_uses_capacity_providers" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.propagate_tags == "SERVICE"
    error_message = "runtime ECS service should propagate service tags to tasks."
  }

  assert {
    condition     = aws_ecs_service.this.enable_ecs_managed_tags == true
    error_message = "runtime ECS service should enable ECS managed tags."
  }

  assert {
    condition     = aws_ecs_service.this.tags.Environment == "test"
    error_message = "runtime ECS service should include caller-provided tags."
  }

  assert {
    condition     = aws_ecs_service.this.tags.Name == "test-stack-runs-on"
    error_message = "runtime ECS service should include the module-computed Name tag."
  }

  assert {
    condition = toset(aws_ecs_cluster_capacity_providers.this.capacity_providers) == toset([
      "FARGATE",
      "FARGATE_SPOT",
    ])
    error_message = "runtime ECS cluster should register both supported Fargate capacity providers."
  }

  assert {
    condition     = length(aws_ecs_service.this.capacity_provider_strategy) == 1
    error_message = "runtime ECS service should use capacity provider strategy, not launch_type."
  }
}

run "empty_ebs_encryption_key_skips_kms_lookup" {
  command = plan

  assert {
    condition     = length(data.aws_kms_key.ebs_encryption) == 0
    error_message = "runtime should not look up a KMS key when ebs_encryption_key_id is empty."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.task.policy).Statement :
      !contains(try(statement.Action, []), "kms:CreateGrant")
    ])
    error_message = "runtime task policy should not include KMS grant permissions without an EBS encryption key."
  }
}

run "ebs_encryption_key_adds_kms_task_policy_statements" {
  command = plan

  variables {
    ebs_encryption_key_id = "alias/aws/ebs"
  }

  assert {
    condition     = length(data.aws_kms_key.ebs_encryption) == 1
    error_message = "runtime should look up the configured EBS KMS key."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.task.policy).Statement :
      contains(try(statement.Action, []), "kms:Decrypt") &&
      statement.Resource == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012" &&
      !can(statement.Condition)
    ])
    error_message = "runtime task policy should grant KMS data-key and encryption operations without a condition."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.task.policy).Statement :
      contains(try(statement.Action, []), "kms:CreateGrant") &&
      statement.Resource == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012" &&
      try(statement.Condition.Bool["kms:GrantIsForAWSResource"], false) == true
    ])
    error_message = "runtime task policy should allow KMS grant creation only for AWS resources."
  }
}

run "managed_task_policy_arns_attach_to_task_role" {
  command = plan

  variables {
    task_role_managed_policy_arns = [
      "arn:aws:iam::123456789012:policy/RunsOnAppCustom",
    ]
  }

  assert {
    condition     = aws_iam_role_policy_attachment.task_managed["arn:aws:iam::123456789012:policy/RunsOnAppCustom"].policy_arn == "arn:aws:iam::123456789012:policy/RunsOnAppCustom"
    error_message = "runtime should attach caller-provided managed policies to the task role."
  }
}

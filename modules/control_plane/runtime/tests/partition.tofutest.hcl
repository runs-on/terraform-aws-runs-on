mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.eu"
      partition  = "aws-eusc"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws-eusc:iam::123456789012:role/test-stack-runtime"
    }
  }
}

variables {
  region                   = "eusc-de-east-1"
  account_id               = "123456789012"
  stack_name               = "test-stack"
  cluster_name             = "test-stack-runtime"
  service_name             = "runs-on"
  task_definition_family   = "test-stack-runtime"
  execution_role_name      = "test-stack-runtime-execution"
  task_role_name           = "test-stack-runtime-task"
  task_policy_name         = "test-stack-runtime-task-policy"
  runner_instance_role_arn = "arn:aws-eusc:iam::123456789012:role/test-stack-runner"
  cache_bucket_arn         = "arn:aws-eusc:s3:::test-stack-cache"
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

run "runtime_policies_use_current_partition" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.execution.policy_arn == "arn:aws-eusc:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    error_message = "ECS execution managed policy ARN should use the current AWS partition."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.task.policy).Statement :
      statement.Action == ["iam:GetRole"] &&
      statement.Resource == "arn:aws-eusc:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
    ])
    error_message = "runtime task service-linked role lookup should use the current AWS partition."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.task.policy).Statement :
      contains(try(statement.Action, []), "ec2:RunInstances") &&
      try(contains(statement.Resource, "arn:aws-eusc:ec2:eusc-de-east-1:123456789012:instance/*"), false) &&
      try(contains(statement.Resource, "arn:aws-eusc:ec2:eusc-de-east-1:123456789012:launch-template/*"), false) &&
      try(contains(statement.Resource, "arn:aws-eusc:ec2:eusc-de-east-1:123456789012:spot-instances-request/*"), false)
    ])
    error_message = "runtime EC2 launch policy should use the current AWS partition."
  }

  assert {
    condition     = output.runtime.service_arn == "arn:aws-eusc:ecs:eusc-de-east-1:123456789012:service/test-stack-runtime/runs-on"
    error_message = "runtime service output ARN should use the current AWS partition."
  }
}

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

variables {
  stack_name                         = "test-plan"
  cache_expiration_days              = 7
  force_destroy_buckets              = true
  vpc_id                             = "vpc-12345678"
  public_subnet_ids                  = ["subnet-private-a", "subnet-private-b"]
  security_group_ids                 = ["sg-runners"]
  tags                               = {}
  prevent_destroy_optional_resources = false
}

run "efs_uses_configured_subnets" {
  command = plan

  variables {
    enable_efs = true
    enable_ecr = false
  }

  assert {
    condition     = length(aws_efs_mount_target.az1) == 1 && aws_efs_mount_target.az1[0].subnet_id == "subnet-private-a"
    error_message = "EFS mount target az1 should use the first configured subnet."
  }

  assert {
    condition     = length(aws_efs_mount_target.az2) == 1 && aws_efs_mount_target.az2[0].subnet_id == "subnet-private-b"
    error_message = "EFS mount target az2 should use the second configured subnet."
  }

  assert {
    condition     = length(aws_security_group.efs) == 1
    error_message = "EFS should create its mount target security group when enabled."
  }

  assert {
    condition     = length(aws_ecr_repository.ephemeral) == 0
    error_message = "ECR repository should not be planned when enable_ecr is false."
  }
}

run "cache_bucket_defaults_to_global_namespace" {
  command = plan

  variables {
    enable_efs = false
    enable_ecr = false
  }

  assert {
    condition     = aws_s3_bucket.cache.bucket_namespace == "global"
    error_message = "Cache bucket should use the global S3 namespace by default."
  }

  assert {
    condition     = aws_s3_bucket.cache.bucket_prefix == "test-plan-cache-"
    error_message = "Global cache bucket should keep the existing bucket prefix naming."
  }
}

run "cache_bucket_can_use_account_regional_namespace" {
  command = plan

  variables {
    cache_bucket_namespace = "account-regional"
    enable_efs             = false
    enable_ecr             = false
  }

  assert {
    condition     = aws_s3_bucket.cache.bucket_namespace == "account-regional"
    error_message = "Cache bucket should allow account-regional S3 namespace."
  }

  assert {
    condition     = aws_s3_bucket.cache.bucket == "test-plan-cache-123456789012-us-east-1-an"
    error_message = "Account-regional cache bucket should include account, region, and -an suffix."
  }
}

run "rejects_invalid_cache_bucket_namespace" {
  command = plan

  variables {
    cache_bucket_namespace = "account_regional"
    enable_efs             = false
    enable_ecr             = false
  }

  expect_failures = [var.cache_bucket_namespace]
}

run "rejects_overlong_account_regional_cache_bucket_name" {
  command = plan

  variables {
    stack_name             = "this-stack-name-is-too-long-for-account-regional-cache-buckets"
    cache_bucket_namespace = "account-regional"
    enable_efs             = false
    enable_ecr             = false
  }

  expect_failures = [aws_s3_bucket.cache]
}

run "ecr_only_skips_efs" {
  command = plan

  variables {
    enable_efs = false
    enable_ecr = true
  }

  assert {
    condition     = length(aws_ecr_repository.ephemeral) == 1
    error_message = "ECR repository should be planned when enable_ecr is true."
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.ephemeral) == 1
    error_message = "ECR lifecycle policy should be planned with the ephemeral repository."
  }

  assert {
    condition     = length(aws_efs_file_system.this_unprotected) == 0 && length(aws_efs_file_system.this_protected) == 0
    error_message = "EFS file systems should not be planned when enable_efs is false."
  }
}

run "optional_resources_disabled" {
  command = plan

  variables {
    enable_efs = false
    enable_ecr = false
  }

  assert {
    condition     = length(aws_efs_file_system.this_unprotected) == 0 && length(aws_efs_file_system.this_protected) == 0
    error_message = "EFS file systems should be absent when enable_efs is false."
  }

  assert {
    condition     = length(aws_ecr_repository.ephemeral) == 0
    error_message = "ECR repository should be absent when enable_ecr is false."
  }
}

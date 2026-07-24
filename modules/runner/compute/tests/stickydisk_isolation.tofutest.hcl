mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.com"
      partition  = "aws"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      unique_id = "AROATESTSTACKROLEID"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/test-stack-ec2-instance-profile"
    }
  }
}

variables {
  region                  = "us-east-1"
  account_id              = "123456789012"
  stack_name              = "test-stack"
  cost_allocation_tag     = "runs-on-stack-name"
  log_retention_days      = 7
  permission_boundary_arn = ""
  app_tag                 = "v0.0.0-test"
  bootstrap_tag           = "v0.0.0-test"
  ipv6_enabled            = false
  runner_max_runtime      = 360
  tags = {
    Environment          = "test"
    "runs-on-stack-name" = "test-stack"
  }

  network = {
    vpc_id             = "vpc-12345678"
    private_mode       = "false"
    public_subnet_ids  = ["subnet-12345678"]
    private_subnet_ids = []
    security_group_ids = ["sg-12345678"]
  }

  extras = {
    cache = {
      bucket_id   = "test-stack-cache"
      bucket_arn  = "arn:aws:s3:::test-stack-cache"
      bucket_name = "test-stack-cache"
    }
    efs = {
      enabled           = false
      file_system_id    = ""
      file_system_arn   = ""
      file_system_dns   = ""
      security_group_id = ""
    }
    ecr = {
      enabled         = false
      repository_arn  = ""
      repository_name = ""
      repository_url  = ""
    }
    pull_through_cache = {
      enabled           = false
      registry_url      = ""
      docker_hub_prefix = ""
      rules             = {}
    }
  }
}

run "stickydisk_isolation_disabled_keeps_legacy_snapshot_policies" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.ec2_snapshot_describe) == 1
    error_message = "Without sticky-disk isolation, the VolumeSnapshotDescribe policy remains for the v1 snapshot action."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_snapshot_create) == 1
    error_message = "Without sticky-disk isolation, the VolumeSnapshotCreate policy remains for the v1 snapshot action."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_snapshot_lifecycle) == 1
    error_message = "Without sticky-disk isolation, the VolumeSnapshotLifecycle policy remains for the v1 snapshot action."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_create_tags_volumes) == 1
    error_message = "Without sticky-disk isolation, the CreateTagsOnVolumesAndSnapshots policy remains for the v1 snapshot action."
  }
}

run "stickydisk_isolation_enabled_removes_runner_ebs_permissions" {
  command = plan

  variables {
    enable_stickydisk_isolation = true
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_snapshot_describe) == 0
    error_message = "With sticky-disk isolation, runners must not be able to describe volumes/snapshots."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_snapshot_create) == 0
    error_message = "With sticky-disk isolation, runners must not be able to create volumes/snapshots."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_snapshot_lifecycle) == 0
    error_message = "With sticky-disk isolation, runners must not be able to attach/delete volumes/snapshots."
  }

  assert {
    condition     = length(aws_iam_role_policy.ec2_create_tags_volumes) == 0
    error_message = "With sticky-disk isolation, runners must not be able to tag volumes/snapshots."
  }
}

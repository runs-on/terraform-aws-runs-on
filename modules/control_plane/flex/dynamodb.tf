# modules/flex_control_plane/dynamodb.tf
# DynamoDB tables for RunsOn core module

###########################
# Locks Table
###########################

resource "aws_dynamodb_table" "locks" {
  name         = "${var.stack_name}-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "key"

  attribute {
    name = "key"
    type = "S"
  }

  ttl {
    enabled        = true
    attribute_name = "expiresAt"
  }

  point_in_time_recovery {
    enabled = var.locks_table_point_in_time_recovery_enabled
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-locks"
    }
  )
}

###########################
# Workflow Jobs Table
###########################

resource "aws_dynamodb_table" "workflow_jobs" {
  name         = "${var.stack_name}-workflow-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute {
    name = "job_id"
    type = "N"
  }

  attribute {
    name = "reconcile_partition"
    type = "S"
  }

  attribute {
    name = "reconcile_after_unix"
    type = "N"
  }

  attribute {
    name = "pending_work_partition"
    type = "S"
  }

  attribute {
    name = "pending_work_not_before_unix"
    type = "N"
  }

  attribute {
    name = "created_at_date"
    type = "S"
  }

  attribute {
    name = "created_at_unix"
    type = "N"
  }

  global_secondary_index {
    name            = "reconcile-index"
    projection_type = "KEYS_ONLY"

    key_schema {
      attribute_name = "reconcile_partition"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "reconcile_after_unix"
      key_type       = "RANGE"
    }
  }

  global_secondary_index {
    name            = "pending-work-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "pending_work_partition"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "pending_work_not_before_unix"
      key_type       = "RANGE"
    }
  }

  global_secondary_index {
    name            = "daily-activity-index"
    projection_type = "INCLUDE"
    non_key_attributes = [
      "installation_id",
      "org_name",
      "repo_name",
      "job_id"
    ]

    key_schema {
      attribute_name = "created_at_date"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "created_at_unix"
      key_type       = "RANGE"
    }
  }

  ttl {
    enabled        = true
    attribute_name = "ttl"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-workflow-jobs"
    }
  )
}

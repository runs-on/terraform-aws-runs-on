# S3 bucket resources for RunsOn cache storage

resource "aws_s3_bucket" "cache" {
  bucket           = var.cache_bucket_namespace == "account-regional" ? local.account_regional_cache_bucket_name : null
  bucket_namespace = var.cache_bucket_namespace
  bucket_prefix    = var.cache_bucket_namespace == "global" ? "${var.stack_name}-cache-" : null
  force_destroy    = var.force_destroy_buckets

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-cache"
    }
  )

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.cache_bucket_namespace != "account-regional" || length(local.account_regional_cache_bucket_name) <= 63
      error_message = "Account-regional cache bucket name must be 63 characters or less. Shorten stack_name."
    }
  }
}

resource "aws_s3_bucket_versioning" "cache" {
  bucket = aws_s3_bucket.cache.id

  versioning_configuration {
    status = var.cache_bucket_versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cache" {
  bucket = aws_s3_bucket.cache.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cache" {
  bucket = aws_s3_bucket.cache.id

  rule {
    id     = "ExpireRunnerConfig"
    status = "Enabled"

    filter {
      prefix = "runners/"
    }

    expiration {
      days = 1
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  rule {
    id     = "ExpireCache"
    status = "Enabled"

    filter {
      prefix = "cache/"
    }

    expiration {
      days = var.cache_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  rule {
    id     = "CleanupIncompleteMultipartUploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "CleanupExpiredObjectDeleteMarkers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cache" {
  bucket = aws_s3_bucket.cache.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cache" {
  bucket = aws_s3_bucket.cache.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cache.arn,
          "${aws_s3_bucket.cache.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

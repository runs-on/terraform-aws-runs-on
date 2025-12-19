# modules/core/sqs.tf
# SQS queues for RunsOn core module

###########################
# Dead Letter Queues
###########################

resource "aws_sqs_queue" "main_dead_letter" {
  name                      = "${var.stack_name}-main-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 259200 # 3 days

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-main-dlq"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "jobs_dead_letter" {
  name                      = "${var.stack_name}-jobs-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 259200 # 3 days

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-jobs-dlq"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "github_dead_letter" {
  name                      = "${var.stack_name}-github-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 259200 # 3 days

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-github-dlq"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "pool_dead_letter" {
  name                      = "${var.stack_name}-pool-dlq"
  message_retention_seconds = 259200 # 3 days

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-pool-dlq"
      Environment = var.environment
    }
  )
}

###########################
# Main Queues
###########################

resource "aws_sqs_queue" "main" {
  name                        = local.queue_main
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 86400
  receive_wait_time_seconds   = 10
  visibility_timeout_seconds  = 120

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.main_dead_letter.arn
    maxReceiveCount     = 3
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-main"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "jobs" {
  name                        = local.queue_jobs
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 86400
  receive_wait_time_seconds   = 10
  visibility_timeout_seconds  = 120

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.jobs_dead_letter.arn
    maxReceiveCount     = 3
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-jobs"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "github" {
  name                        = local.queue_github
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 86400
  receive_wait_time_seconds   = 10
  visibility_timeout_seconds  = 120 # GitHub API calls + S3 uploads

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.github_dead_letter.arn
    maxReceiveCount     = 3
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-github"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "pool" {
  name                       = local.queue_pool
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 120

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pool_dead_letter.arn
    maxReceiveCount     = 3
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-pool"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "housekeeping" {
  name                       = local.queue_housekeeping
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 120

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-housekeeping"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "termination" {
  name                       = local.queue_termination
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 120

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-termination"
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "events" {
  name                       = local.queue_events
  message_retention_seconds  = 7200
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 120

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-events"
      Environment = var.environment
    }
  )
}

###########################
# Queue Policies
###########################

resource "aws_sqs_queue_policy" "main_dead_letter" {
  queue_url = aws_sqs_queue.main_dead_letter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.main_dead_letter.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sqs_queue.main.arn
          }
        }
      }
    ]
  })
}

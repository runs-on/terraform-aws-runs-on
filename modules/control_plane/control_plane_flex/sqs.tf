# modules/flex_control_plane/sqs.tf
# SQS queues for RunsOn core module

###########################
# Dead Letter Queues
###########################

resource "aws_sqs_queue" "webhooks_dead_letter" {
  name                      = "${var.stack_name}-webhooks-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 259200 # 3 days
  sqs_managed_sse_enabled   = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-webhooks-dlq"
    }
  )
}

resource "aws_sqs_queue" "system_dead_letter" {
  name                      = "${var.stack_name}-system-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 259200 # 3 days
  sqs_managed_sse_enabled   = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-system-dlq"
    }
  )
}

###########################
# Main Queues
###########################

resource "aws_sqs_queue" "webhooks" {
  name                        = "${var.stack_name}-webhooks.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  message_retention_seconds   = 86400
  receive_wait_time_seconds   = 10
  visibility_timeout_seconds  = 120
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhooks_dead_letter.arn
    maxReceiveCount     = 3
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-webhooks"
    }
  )
}

resource "aws_sqs_queue" "system" {
  name                        = "${var.stack_name}-system.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 86400
  receive_wait_time_seconds   = 10
  visibility_timeout_seconds  = 120
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.system_dead_letter.arn
    maxReceiveCount     = 3
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-system"
    }
  )
}

resource "aws_sqs_queue" "events" {
  name                       = "${var.stack_name}-events"
  message_retention_seconds  = 7200
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 120
  sqs_managed_sse_enabled    = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-events"
    }
  )
}

###########################
# Queue Policies
###########################

resource "aws_sqs_queue_policy" "webhooks_dead_letter" {
  queue_url = aws_sqs_queue.webhooks_dead_letter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.webhooks_dead_letter.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sqs_queue.webhooks.arn
          }
        }
      }
    ]
  })
}

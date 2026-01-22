# modules/core/eventbridge.tf
# EventBridge rules for RunsOn core module

###########################
# Spot Instance Interruption Events
###########################

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.stack_name}-spot-interruption"
  description = "Capture EC2 Spot Instance interruption warnings"

  event_pattern = jsonencode({
    source = ["aws.ec2"]
    detail-type = [
      "EC2 Spot Instance Interruption Warning",
      "EC2 Instance State-change Notification"
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-spot-interruption"
    }
  )
}

resource "aws_cloudwatch_event_target" "spot_interruption_to_sqs" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.events.arn
}

###########################
# SQS Queue Policy for EventBridge
###########################

resource "aws_sqs_queue_policy" "events_eventbridge" {
  queue_url = aws_sqs_queue.events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.events.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.spot_interruption.arn
          }
        }
      }
    ]
  })
}

###########################
# Scheduled Events (Optional - for cost reports)
###########################

resource "aws_scheduler_schedule" "cost_report" {
  count = var.enable_cost_reports ? 1 : 0

  name                         = "${var.stack_name}-cost-report"
  schedule_expression          = "cron(5 0 * * ? *)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.events.arn
    role_arn = aws_iam_role.scheduler[0].arn

    retry_policy {
      maximum_retry_attempts = 0
    }

    input = jsonencode({
      "detail-type" = "RunsOn Cost Report"
    })
  }
}

resource "aws_scheduler_schedule" "cost_allocation_tag" {
  count = var.enable_cost_reports ? 1 : 0

  name                         = "${var.stack_name}-cost-allocation-tag"
  schedule_expression          = "cron(10 0 * * ? *)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.events.arn
    role_arn = aws_iam_role.scheduler[0].arn

    retry_policy {
      maximum_retry_attempts = 0
    }

    input = jsonencode({
      "detail-type" = "RunsOn Cost Allocation Tag"
    })
  }
}

###########################
# Scheduler IAM Role
###########################

resource "aws_iam_role" "scheduler" {
  count = var.enable_cost_reports ? 1 : 0

  name = "${var.stack_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-scheduler-role"
    }
  )
}

resource "aws_iam_role_policy" "scheduler_sqs" {
  count = var.enable_cost_reports ? 1 : 0

  name = "SendToSQS"
  role = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.events.arn
      }
    ]
  })
}

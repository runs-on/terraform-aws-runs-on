# modules/flex_control_plane/cloudwatch.tf
# CloudWatch dashboard and budget for RunsOn core module

###########################
# Worker Daily Cost Budget
###########################

resource "aws_budgets_budget" "app_daily_budget" {
  account_id        = var.account_id
  name              = "${var.stack_name}-app-daily-budget"
  budget_type       = "COST"
  limit_amount      = tostring(local.operations.app_budget_daily_usd)
  limit_unit        = "USD"
  time_unit         = "DAILY"
  time_period_start = "2024-01-01_00:00"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:%s$%s", var.cost_allocation_tag, var.stack_name)]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    notification_type         = "ACTUAL"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }
}

###########################
# CloudWatch Dashboard
###########################

resource "aws_cloudwatch_dashboard" "runs_on" {
  dashboard_name = "${var.stack_name}-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.webhooks.name]
          ]
          period = 300
          stat   = "Maximum"
          region = var.region
          title  = "Webhook Messages Queued"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 6
        y      = 0
        width  = 6
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_event\" and status = \"scheduled\"\n| stats count() as RunnersScheduled"
          region = var.region
          title  = "Total Runners Scheduled (Current Period)"
          view   = "table"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 0
        width  = 6
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_event\" and status = \"scheduled\"\n| stats count() as RunnersScheduled by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "Runners Scheduled over time (5min intervals)"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 18
        y      = 0
        width  = 6
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_event\" and ispresent(overall_queue_duration_seconds)\n| stats pct(internal_queue_duration_seconds, 90) as internal_P90, pct(internal_queue_duration_seconds, 50) as internal_P50, pct(overall_queue_duration_seconds, 90) as overall_P90, pct(overall_queue_duration_seconds, 50) as overall_P50 by bin(1m) as t\n| sort t asc"
          region = var.region
          title  = "Internal/Overall Queue Duration Percentiles (P50/P90)"
          view   = "timeSeries"
          yAxis = {
            left = {
              min   = 0
              label = "Seconds"
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, jobs_conclusion.success as count_success, jobs_conclusion.failure as count_failure, jobs_conclusion.cancelled as count_cancelled, jobs_conclusion.skipped as count_skipped\n| stats max(count_success) as success, max(count_failure) as failure, max(count_cancelled) as cancelled, max(count_skipped) as skipped by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "Completed Jobs by Conclusion"
          view   = "stackedArea"
        }
      },
      {
        type   = "log"
        x      = 8
        y      = 6
        width  = 4
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_read.tokens as limiter_tokens, rate_limiters.ec2_read.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "EC2 Read"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 4
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_run.tokens as limiter_tokens, rate_limiters.ec2_run.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "EC2 Run"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 16
        y      = 6
        width  = 4
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_terminate.tokens as limiter_tokens, rate_limiters.ec2_terminate.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "EC2 Terminate"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 20
        y      = 6
        width  = 4
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_mutating.tokens as limiter_tokens, rate_limiters.ec2_mutating.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc" # gitleaks:allow
          region = var.region
          title  = "EC2 Mutating"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 4
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.s3.tokens as limiter_tokens, rate_limiters.s3.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc" # gitleaks:allow
          region = var.region
          title  = "S3 API"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 4
        y      = 12
        width  = 4
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.github.tokens as limiter_tokens, rate_limiters.github.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "GitHub API"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 8
        y      = 12
        width  = 16
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter level = \"error\"\n| fields @timestamp, message\n| sort @timestamp desc\n| limit 50"
          region = var.region
          title  = "Recent Error Messages (Latest 50)"
          view   = "table"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| stats min(jobs.queued) as queued, min(jobs.scheduled) as scheduled, min(jobs.in_progress) as in_progress, min(jobs.completed) as completed by bin(1m) as t\n| sort t asc"
          region = var.region
          title  = "Job Status Summary"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, spot_circuit_breaker.active as active, spot_circuit_breaker.interruption_count as interruption_count\n| stats min(active) as circuit_breaker_active, min(interruption_count) as interruptions by bin(1m) as t\n| sort t asc"
          region = var.region
          title  = "Spot Circuit Breaker Status"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 24
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"spot_interruption\"\n| fields @timestamp, interruption_time, trip_count, recovery_minutes, circuit_breaker_active\n| sort @timestamp desc\n| limit 50"
          region = var.region
          title  = "Recent Spot Interruptions (Last 50)"
          view   = "table"
        }
      }
    ]
  })
}

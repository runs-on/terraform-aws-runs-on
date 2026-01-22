# modules/core/cloudwatch.tf
# CloudWatch Alarms for RunsOn core module

###########################
# App Runner Daily Budget Alarm
###########################

resource "aws_cloudwatch_metric_alarm" "app_daily_budget" {
  alarm_name          = "${var.stack_name}-app-daily-budget"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ActiveInstances"
  namespace           = "AWS/AppRunner"
  period              = "86400" # 1 day
  statistic           = "Sum"
  threshold           = var.app_alarm_daily_minutes
  alarm_description   = "Alarm when App Runner active instances exceed daily budget"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = aws_apprunner_service.this.service_name
    ServiceArn  = aws_apprunner_service.this.arn
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.stack_name}-app-daily-budget"
      AlarmType = "budget"
    }
  )
}

###########################
# SQS Oldest Message Alarms
###########################

resource "aws_cloudwatch_metric_alarm" "sqs_main_oldest_message" {
  count = var.sqs_queue_oldest_message_threshold_seconds > 0 ? 1 : 0

  alarm_name          = "${var.stack_name}-sqs-main-oldest-message"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = var.sqs_queue_oldest_message_threshold_seconds
  alarm_description   = "Alarm when SQS main queue oldest message exceeds threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.stack_name}-sqs-main-oldest-message"
      AlarmType = "sqs-monitoring"
    }
  )
}

# Note: Similar alarms can be created for other queues (jobs, termination, etc.)

###########################
# CloudWatch Dashboard (Optional)
###########################

resource "aws_cloudwatch_dashboard" "runs_on" {
  count = var.enable_dashboard ? 1 : 0

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
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.main.name]
          ]
          period = 300
          stat   = "Maximum"
          region = var.region
          title  = "Jobs Currently Queued"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter message like /🎉 Runner scheduled successfully/\n| stats count() as RunnersScheduled"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| fields @timestamp\n| filter message like /🎉 Runner scheduled successfully/\n| stats count() as RunnersScheduled by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"job_event\" and ispresent(overall_queue_duration_seconds)\n| | stats pct(internal_queue_duration_seconds, 90) as internal_P90, pct(internal_queue_duration_seconds, 50) as internal_P50, pct(overall_queue_duration_seconds, 90) as overall_P90, pct(overall_queue_duration_seconds, 50) as overall_P50 by bin(1m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, jobs_conclusion.success as count_success, jobs_conclusion.failure as count_failure, jobs_conclusion.cancelled as count_cancelled, jobs_conclusion.skipped as count_skipped\n| stats max(count_success) as success, max(count_failure) as failure, max(count_cancelled) as cancelled, max(count_skipped) as skipped by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_read.tokens as tokens, rate_limiters.ec2_read.burst as burst\n| stats avg(tokens) as avg_tokens, avg(burst) as avg_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_run.tokens as tokens, rate_limiters.ec2_run.burst as burst\n| stats avg(tokens) as avg_tokens, avg(burst) as avg_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_terminate.tokens as tokens, rate_limiters.ec2_terminate.burst as burst\n| stats avg(tokens) as avg_tokens, avg(burst) as avg_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.ec2_mutating.tokens as tokens, rate_limiters.ec2_mutating.burst as burst\n| stats avg(tokens) as avg_tokens, avg(burst) as avg_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.s3.tokens as tokens, rate_limiters.s3.burst as burst\n| stats avg(tokens) as avg_tokens, avg(burst) as avg_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, rate_limiters.github.tokens as tokens, rate_limiters.github.burst as burst\n| stats avg(tokens) as avg_tokens, avg(burst) as avg_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter level = \"error\"\n| fields @timestamp, message\n| sort @timestamp desc\n| limit 50"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| stats min(jobs.queued) as queued, min(jobs.scheduled) as scheduled, min(jobs.in_progress) as in_progress, min(jobs.completed) as completed by bin(1m) as t\n| sort t asc"
          region = var.region
          title  = "Job Status Summary"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\" and ispresent(pools.0.dangling)\n| parse @message /\\[(?<pool_data>.*)\\]/\n| parse pool_data /\"pool_name\":\"(?<pool_name>[^\"]+)\"/\n| parse pool_data /\"hot\":(?<hot>\\d+)/\n| parse pool_data /\"stopped\":(?<stopped>\\d+)/\n| parse pool_data /\"warming\":(?<warming>\\d+)/\n| parse pool_data /\"ready\":(?<ready>\\d+)/\n| parse pool_data /\"ready_to_stop\":(?<ready_to_stop>\\d+)/\n| parse pool_data /\"detached\":(?<detached>\\d+)/\n| parse pool_data /\"error\":(?<error>\\d+)/\n| parse pool_data /\"outdated\":(?<outdated>\\d+)/\n| parse pool_data /\"dangling\":(?<dangling>\\d+)/\n| stats max(hot) as max_hot, max(stopped) as max_stopped, max(warming) as max_warming, max(ready) as max_ready, max(ready_to_stop) as max_ready_to_stop, max(detached) as max_detached, max(error) as max_error, max(outdated) as max_outdated, max(dangling) as max_dangling by bin(5m) as t, pool_name\n| sort t desc, pool_name asc"
          region = var.region
          title  = "Pool Instances Over Time"
          view   = "table"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"snapshot\"\n| fields @timestamp, spot_circuit_breaker.active as active, spot_circuit_breaker.interruption_count as interruption_count\n| stats min(active) as circuit_breaker_active, min(interruption_count) as interruptions by bin(1m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.apprunner_log_group_name}'\n| filter metric_type = \"spot_interruption\"\n| fields @timestamp, interruption_time, trip_count, recovery_minutes, circuit_breaker_active\n| sort @timestamp desc\n| limit 50"
          region = var.region
          title  = "Recent Spot Interruptions (Last 50)"
          view   = "table"
        }
      }
    ]
  })
}

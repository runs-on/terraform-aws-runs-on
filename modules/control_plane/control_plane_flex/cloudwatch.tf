# modules/flex_control_plane/cloudwatch.tf
# CloudWatch dashboard for RunsOn core module
# Log query values are generated from scripts/cloudwatch-queries.toml.

###########################
# CloudWatch Dashboard
###########################

locals {
  # Also linked from the setup status page.
  dashboard_name = "${var.stack_name}-Dashboard"
}

resource "aws_cloudwatch_dashboard" "runs_on" {
  count = local.operations.enable_default_dashboard ? 1 : 0

  dashboard_name = local.dashboard_name

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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_launched\"\n| stats count() as JobsLaunched"
          region = var.region
          title  = "Total Jobs Launched (Current Period)"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_launched\"\n| stats count() as JobsLaunched by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "Jobs Launched over time (5min intervals)"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_summary\"\n| stats pct(overall_queue_duration_seconds, 50) as queue_P50, pct(overall_queue_duration_seconds, 95) as queue_P95, pct(job_duration_seconds, 50) as job_P50, pct(job_duration_seconds, 95) as job_P95 by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "Queue/Job Duration Percentiles (P50/P95)"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_summary\"\n| stats sum(if(conclusion = \"success\", 1, 0)) as success, sum(if(conclusion = \"failure\", 1, 0)) as failure, sum(if(conclusion = \"cancelled\", 1, 0)) as cancelled, sum(if(conclusion = \"skipped\", 1, 0)) as skipped by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields @timestamp, rate_limiters.ec2_read.tokens as limiter_tokens, rate_limiters.ec2_read.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields @timestamp, rate_limiters.ec2_run.tokens as limiter_tokens, rate_limiters.ec2_run.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields @timestamp, rate_limiters.ec2_terminate.tokens as limiter_tokens, rate_limiters.ec2_terminate.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields @timestamp, rate_limiters.ec2_mutating.tokens as limiter_tokens, rate_limiters.ec2_mutating.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc" # gitleaks:allow
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields @timestamp, rate_limiters.s3.tokens as limiter_tokens, rate_limiters.s3.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc" # gitleaks:allow
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields @timestamp, rate_limiters.github.tokens as limiter_tokens, rate_limiters.github.burst as limiter_burst\n| stats avg(limiter_tokens) as avg_limiter_tokens, avg(limiter_burst) as avg_limiter_burst by bin(5m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields reconciler_backlog, provisioning_backlog.launch as launch_backlog, provisioning_backlog.registration as registration_backlog\n| stats max(reconciler_backlog) as reconciler, max(launch_backlog) as launch, max(registration_backlog) as registration by bin(1m) as t\n| sort t asc"
          region = var.region
          title  = "Control Plane Backlog"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_summary\" and conclusion in [\"success\", \"failure\"]\n| stats sum(if(conclusion = \"failure\", 1, 0)) / count() as FailureRate by bin(30m) as t\n| sort t asc"
          region = var.region
          title  = "Job Failure Rate (30min intervals)"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| fields @timestamp, spot_circuit_breaker.active as active\n| stats max(active) as circuit_breaker_active by bin(1m) as t\n| sort t asc"
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
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"job_summary\" and ispresent(estimated_cost_usd)\n| stats pct(estimated_cost_usd, 50) as CostP50, pct(estimated_cost_usd, 95) as CostP95 by bin(30m) as t\n| sort t asc"
          region = var.region
          title  = "Estimated Job Cost (P50/P95)"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 30
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"spot_interruption\"\n| fields @timestamp, interruption_time, trip_count, recovery_minutes, circuit_breaker_active\n| sort @timestamp desc\n| limit 50"
          region = var.region
          title  = "Recent Spot Interruptions (Last 50)"
          view   = "table"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 36
        width  = 9
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| stats max(runner_vcpus_total) as vCPUs by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "Runner vCPUs (5min peaks)"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 9
        y      = 36
        width  = 9
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| stats max(jobs_in_progress_total) as JobsInProgress by bin(5m) as t\n| sort t asc"
          region = var.region
          title  = "Jobs in Progress (5min peaks)"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 18
        y      = 36
        width  = 6
        height = 6
        properties = {
          query  = "SOURCE '${local.worker_log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| stats max(runner_vcpus_total) as PeakVCPUs, latest(runner_vcpus_total) as CurrentVCPUs, max(jobs_in_progress_total) as PeakJobsInProgress, latest(jobs_in_progress_total) as CurrentJobsInProgress"
          region = var.region
          title  = "Runner Usage (Current Period)"
          view   = "table"
        }
      }
    ]
  })
}

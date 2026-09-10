# Log query values are generated from scripts/cloudwatch-queries.toml.
resource "aws_cloudwatch_dashboard" "fleet" {
  dashboard_name = "${var.stack_name}-Fleet-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "log", x = 0, y = 0, width = 6, height = 6
        properties = {
          query  = "SOURCE '${module.runtime.runtime.log_group_name}'\n| filter metric_type = \"job_launched\"\n| stats count() as JobsLaunched by bin(5m) as t\n| sort t asc"
          region = var.region, title = "Jobs Launched", view = "timeSeries"
        }
      },
      {
        type = "log", x = 6, y = 0, width = 6, height = 6
        properties = {
          query  = "SOURCE '${module.runtime.runtime.log_group_name}'\n| filter metric_type = \"job_summary\"\n| stats pct(overall_queue_duration_seconds, 50) as QueueP50, pct(overall_queue_duration_seconds, 95) as QueueP95, pct(job_duration_seconds, 50) as JobP50, pct(job_duration_seconds, 95) as JobP95 by bin(5m) as t\n| sort t asc"
          region = var.region, title = "Queue/Job Duration (P50/P95)", view = "timeSeries"
        }
      },
      {
        type = "log", x = 12, y = 0, width = 6, height = 6
        properties = {
          query  = "SOURCE '${module.runtime.runtime.log_group_name}'\n| filter metric_type = \"job_summary\" and ispresent(estimated_cost_usd)\n| stats pct(estimated_cost_usd, 50) as CostP50, pct(estimated_cost_usd, 95) as CostP95 by bin(30m) as t\n| sort t asc"
          region = var.region, title = "Estimated Job Cost (P50/P95)", view = "timeSeries"
        }
      },
      {
        type = "log", x = 18, y = 0, width = 6, height = 6
        properties = {
          query  = "SOURCE '${module.runtime.runtime.log_group_name}'\n| filter metric_type = \"job_summary\" and conclusion in [\"success\", \"failure\"]\n| stats sum(if(conclusion = \"failure\", 1, 0)) / count() as FailureRate by bin(30m) as t\n| sort t asc"
          region = var.region, title = "Job Failure Rate", view = "timeSeries"
        }
      },
      {
        type = "log", x = 0, y = 6, width = 12, height = 6
        properties = {
          query  = "SOURCE '${module.runtime.runtime.log_group_name}'\n| filter metric_type = \"operator_snapshot\"\n| stats max(fleet_desired_runners_total) as DesiredRunners, max(fleet_claims_total) as Claims by bin(5m) as t\n| sort t asc"
          region = var.region, title = "Fleet Desired Runners and Claims", view = "timeSeries"
        }
      },
      {
        type = "log", x = 12, y = 6, width = 12, height = 6
        properties = {
          query  = "SOURCE '${module.runtime.runtime.log_group_name}'\n| filter level = \"error\" or metric_type = \"spot_interruption\"\n| fields @timestamp, metric_type, message, instance_id, repo_full_name\n| sort @timestamp desc\n| limit 50"
          region = var.region, title = "Recent Incidents", view = "table"
        }
      }
    ]
  })
}

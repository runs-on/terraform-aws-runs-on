# Scheduled GitHub runner mirror refresh for outdated runner retry recovery.

data "archive_file" "github_runner_cache_refresh" {
  type        = "zip"
  output_path = "${local.lambda_artifact_prefix}-github-runner-cache-refresh.zip"

  source {
    content  = file("${path.module}/../../../lambdas/github_runner_cache_refresh.js")
    filename = "index.js"
  }
}

resource "aws_cloudwatch_log_group" "github_runner_cache_refresh_lambda" {
  name              = "/aws/lambda/${var.stack_name}-github-runner-cache-refresh"
  retention_in_days = 14

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-runner-cache-refresh-lambda"
    }
  )
}

resource "aws_iam_role" "github_runner_cache_refresh" {
  name = "${var.stack_name}-github-runner-cache-refresh-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-runner-cache-refresh-role"
    }
  )
}

resource "aws_iam_role_policy" "github_runner_cache_refresh_logs" {
  name = "RunsOnGitHubRunnerCacheRefreshLogPermissions"
  role = aws_iam_role.github_runner_cache_refresh.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.github_runner_cache_refresh_lambda.arn}:*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "github_runner_cache_refresh" {
  name = "RunsOnGitHubRunnerCacheRefreshPermissions"
  role = aws_iam_role.github_runner_cache_refresh.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = var.extras.cache.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "agents/github-runner",
              "agents/github-runner/*",
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${var.extras.cache.bucket_arn}/agents/github-runner/*"
      },
    ]
  })
}

resource "aws_lambda_function" "github_runner_cache_refresh" {
  function_name = "${var.stack_name}-github-runner-cache-refresh"
  role          = aws_iam_role.github_runner_cache_refresh.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.github_runner_cache_refresh.output_path
  source_code_hash = data.archive_file.github_runner_cache_refresh.output_base64sha256

  environment {
    variables = {
      RUNS_ON_RUNNER_CACHE_BUCKET = var.extras.cache.bucket_name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-runner-cache-refresh"
    }
  )

  depends_on = [
    aws_iam_role_policy.github_runner_cache_refresh_logs,
  ]
}

resource "aws_lambda_invocation" "github_runner_cache_refresh_seed" {
  function_name = aws_lambda_function.github_runner_cache_refresh.function_name
  input = jsonencode({
    input = {
      bucket = var.extras.cache.bucket_name
    }
  })

  depends_on = [
    aws_iam_role_policy.github_runner_cache_refresh,
  ]
}

resource "aws_scheduler_schedule" "github_runner_cache_refresh" {
  name                         = "${var.stack_name}-github-runner-cache-refresh"
  schedule_expression          = "cron(15 0 * * ? *)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.github_runner_cache_refresh.arn
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_retry_attempts = 0
    }

    input = jsonencode({})
  }
}

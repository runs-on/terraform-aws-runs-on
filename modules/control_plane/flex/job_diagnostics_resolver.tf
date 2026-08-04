resource "aws_cloudwatch_log_group" "job_diagnostics_resolver" {
  name              = "/runs-on/${var.stack_name}/lambda/job-diagnostics-resolver"
  retention_in_days = 14

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-job-diagnostics-resolver"
    }
  )
}

resource "aws_iam_role" "job_diagnostics_resolver" {
  name = "${var.stack_name}-job-diagnostics-resolver-role"

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
      Name = "${var.stack_name}-job-diagnostics-resolver-role"
    }
  )
}

resource "aws_iam_role_policy" "job_diagnostics_resolver" {
  name = "RunsOnJobDiagnosticsResolverPermissions"
  role = aws_iam_role.job_diagnostics_resolver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          aws_secretsmanager_secret.runs_on_stack_config.arn,
          aws_secretsmanager_secret.runs_on_github_apps.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
        ]
        Resource = aws_dynamodb_table.workflow_jobs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.job_diagnostics_resolver.arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "job_diagnostics_resolver" {
  function_name = "${var.stack_name}-job-diagnostics-resolver"
  role          = aws_iam_role.job_diagnostics_resolver.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  timeout       = 30
  memory_size   = 256

  filename         = "${local.lambda_artifact_dir}/job-diagnostics-resolver.zip"
  source_code_hash = filebase64sha256("${local.lambda_artifact_dir}/job-diagnostics-resolver.zip")

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.job_diagnostics_resolver.name
  }

  environment {
    variables = {
      RUNS_ON_PRODUCT                     = "flex"
      RUNS_ON_STACK_NAME                  = var.stack_name
      RUNS_ON_STACK_CONFIG_SECRET_ARN     = aws_secretsmanager_secret.runs_on_stack_config.arn
      RUNS_ON_STACK_CONFIG_SECRET_VERSION = local.stack_config_secret_version
      RUNS_ON_GITHUB_APPS_SECRET_ARN      = aws_secretsmanager_secret.runs_on_github_apps.arn
      RUNS_ON_WORKFLOW_JOBS_TABLE         = aws_dynamodb_table.workflow_jobs.name
      RUNS_ON_GITHUB_ENTERPRISE_URL       = local.github.enterprise_url
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-job-diagnostics-resolver"
    }
  )

  depends_on = [
    aws_cloudwatch_log_group.job_diagnostics_resolver,
  ]
}

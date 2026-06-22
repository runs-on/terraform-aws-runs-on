data "archive_file" "job_diagnostics_resolver" {
  type        = "zip"
  output_path = "${path.root}/.terraform/runs-on-${substr(sha1(var.stack_name), 0, 8)}-${var.stack_name}-job-diagnostics-resolver.zip"

  source {
    content  = file("${path.module}/../../../lambdas/job_diagnostics_resolver.js")
    filename = "index.js"
  }
}

resource "aws_cloudwatch_log_group" "job_diagnostics_resolver" {
  name              = "/runs-on/${var.stack_name}/lambda/job-diagnostics-resolver"
  retention_in_days = 14
  tags              = var.tags
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

  tags = var.tags
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
        Resource = aws_secretsmanager_secret.config.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:UpdateItem",
        ]
        Resource = [
          aws_dynamodb_table.claims.arn,
          "${aws_dynamodb_table.claims.arn}/index/workflow-run-id-index",
        ]
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

  filename         = data.archive_file.job_diagnostics_resolver.output_path
  source_code_hash = data.archive_file.job_diagnostics_resolver.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.job_diagnostics_resolver.name
  }

  environment {
    variables = {
      RUNS_ON_PRODUCT                 = "fleet"
      RUNS_ON_FLEET_CONFIG_SECRET_ARN = aws_secretsmanager_secret.config.arn
      RUNS_ON_CLAIMS_TABLE            = aws_dynamodb_table.claims.name
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-job-diagnostics-resolver"
    }
  )

  depends_on = [
    aws_cloudwatch_log_group.job_diagnostics_resolver,
  ]
}

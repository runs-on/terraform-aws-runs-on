# modules/flex_control_plane/secrets.tf
# Secrets used by the worker runtime and setup flow

resource "aws_secretsmanager_secret" "runs_on_stack_config" {
  name                    = local.stack_config_secret_id
  description             = "RunsOn stack configuration for the worker runtime and tooling"
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-stack-config"
    }
  )
}

resource "aws_cloudwatch_log_group" "stack_config_materializer" {
  name              = "/runs-on/${var.stack_name}/lambda/stack-config-materializer"
  retention_in_days = 14

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-stack-config-materializer"
    }
  )
}

resource "aws_iam_role" "stack_config_materializer" {
  name = "${var.stack_name}-stack-config-materializer-role"

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
      Name = "${var.stack_name}-stack-config-materializer-role"
    }
  )
}

resource "aws_iam_role_policy" "stack_config_materializer" {
  name = "RunsOnStackConfigMaterializerPermissions"
  role = aws_iam_role.stack_config_materializer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:PutSecretValue",
        ]
        Resource = aws_secretsmanager_secret.runs_on_stack_config.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.stack_config_materializer.arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "stack_config_materializer" {
  function_name = "${var.stack_name}-stack-config-materializer"
  role          = aws_iam_role.stack_config_materializer.arn
  runtime       = "python3.14"
  handler       = "index.handler"
  timeout       = 30
  memory_size   = 128

  filename         = "${local.lambda_artifact_dir}/stack-config-materializer.zip"
  source_code_hash = filebase64sha256("${local.lambda_artifact_dir}/stack-config-materializer.zip")

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.stack_config_materializer.name
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-stack-config-materializer"
    }
  )

  depends_on = [
    aws_cloudwatch_log_group.stack_config_materializer,
  ]
}

resource "aws_lambda_invocation" "stack_config_materializer" {
  function_name = aws_lambda_function.stack_config_materializer.function_name
  # Publish the stack config without letting Terraform own Secrets Manager staging labels.
  input = jsonencode({
    secret_id            = aws_secretsmanager_secret.runs_on_stack_config.arn
    secret_string        = local.stack_config_json
    client_request_token = local.stack_config_client_request_token
  })
  triggers = {
    lambda_version       = aws_lambda_function.stack_config_materializer.source_code_hash
    secret_id            = aws_secretsmanager_secret.runs_on_stack_config.arn
    client_request_token = local.stack_config_client_request_token
  }

  depends_on = [
    aws_iam_role_policy.stack_config_materializer,
  ]
}

resource "aws_secretsmanager_secret" "runs_on_github_apps" {
  name                    = "/runs-on/${var.stack_name}/github-apps"
  description             = "RunsOn GitHub apps configuration"
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-apps"
    }
  )
}

resource "aws_secretsmanager_secret_version" "runs_on_github_apps" {
  # The shared secret must exist for the interactive setup flow, but it starts
  # without a version until Terraform is given declarative GitHub App config.
  count = var.github.apps != null ? 1 : 0

  secret_id     = aws_secretsmanager_secret.runs_on_github_apps.id
  secret_string = jsonencode(var.github.apps)
}

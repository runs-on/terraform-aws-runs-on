# modules/flex_control_plane/ingress.tf
# Public ingress API for setup, readiness, and webhook delivery

data "archive_file" "public_ingress" {
  type        = "zip"
  output_path = "${local.lambda_artifact_prefix}-public-ingress.zip"

  source {
    content  = file("${path.module}/../../../lambdas/github_webhooks.js")
    filename = "index.js"
  }
}

data "archive_file" "github_apps_setup" {
  count       = local.admin_routes_enabled ? 1 : 0
  type        = "zip"
  output_path = "${local.lambda_artifact_prefix}-github-apps-setup.zip"

  source {
    content  = file("${path.module}/../../../lambdas/github_apps_setup.js")
    filename = "index.js"
  }
}

resource "aws_cloudwatch_log_group" "public_ingress_lambda" {
  name              = "/aws/lambda/${var.stack_name}-public-ingress"
  retention_in_days = 14

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-public-ingress-lambda"
    }
  )
}

resource "aws_cloudwatch_log_group" "github_apps_setup_lambda" {
  count             = local.admin_routes_enabled ? 1 : 0
  name              = "/aws/lambda/${var.stack_name}-github-apps-setup"
  retention_in_days = 14

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-apps-setup-lambda"
    }
  )
}

resource "aws_iam_role" "public_ingress" {
  name = "${var.stack_name}-public-ingress-role"

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
      Name = "${var.stack_name}-public-ingress-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "public_ingress_logs" {
  role       = aws_iam_role.public_ingress.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "public_ingress" {
  name = "RunsOnPublicIngressPermissions"
  role = aws_iam_role.public_ingress.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
        ]
        Resource = aws_sqs_queue.webhooks.arn
      },
    ]
  })
}

resource "aws_lambda_function" "public_ingress" {
  function_name = "${var.stack_name}-public-ingress"
  role          = aws_iam_role.public_ingress.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  timeout       = 15
  memory_size   = 256

  filename         = data.archive_file.public_ingress.output_path
  source_code_hash = data.archive_file.public_ingress.output_base64sha256

  environment {
    variables = {
      RUNS_ON_WEBHOOKS_QUEUE_URL = aws_sqs_queue.webhooks.url
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-public-ingress"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.public_ingress_logs,
  ]
}

resource "aws_iam_role" "github_apps_setup" {
  count = local.admin_routes_enabled ? 1 : 0
  name  = "${var.stack_name}-github-apps-setup-role"

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
      Name = "${var.stack_name}-github-apps-setup-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "github_apps_setup_logs" {
  count      = local.admin_routes_enabled ? 1 : 0
  role       = aws_iam_role.github_apps_setup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "github_apps_setup" {
  count = local.admin_routes_enabled ? 1 : 0
  name  = "RunsOnGitHubAppsSetupPermissions"
  role  = aws_iam_role.github_apps_setup[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:PutSecretValue",
        ]
        Resource = aws_secretsmanager_secret.runs_on_github_apps.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          aws_secretsmanager_secret.runs_on_github_apps.arn,
          aws_secretsmanager_secret.runs_on_stack_config.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = aws_ssm_parameter.license_status.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:ListSubscriptionsByTopic",
        ]
        Resource = module.alerts.topic_arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:CreateServiceLinkedRole",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
        ]
        Resource = aws_sqs_queue.system.arn
      },
    ]
  })
}

resource "aws_lambda_function" "github_apps_setup" {
  count         = local.admin_routes_enabled ? 1 : 0
  function_name = "${var.stack_name}-github-apps-setup"
  role          = aws_iam_role.github_apps_setup[0].arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  timeout       = 15
  memory_size   = 256

  filename         = data.archive_file.github_apps_setup[0].output_path
  source_code_hash = data.archive_file.github_apps_setup[0].output_base64sha256

  environment {
    variables = {
      RUNS_ON_GITHUB_ORG                   = local.github.organization
      RUNS_ON_GITHUB_ENTERPRISE_URL        = local.github.enterprise_url
      RUNS_ON_GITHUB_APPS_SECRET_ARN       = aws_secretsmanager_secret.runs_on_github_apps.arn
      RUNS_ON_STACK_CONFIG_SECRET_ARN      = aws_secretsmanager_secret.runs_on_stack_config.arn
      RUNS_ON_STACK_CONFIG_SECRET_VERSION  = local.stack_config_secret_version
      RUNS_ON_LICENSE_STATUS_SSM_PARAMETER = aws_ssm_parameter.license_status.name
      RUNS_ON_APP_TAG                      = local.runtime.tag
      RUNS_ON_PUBLIC_BASE_URL              = local.public_ingress_base_url
      RUNS_ON_TOPIC_ARN                    = module.alerts.topic_arn
      RUNS_ON_SYSTEM_QUEUE_URL             = aws_sqs_queue.system.url
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-github-apps-setup"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.github_apps_setup_logs[0],
  ]
}

resource "aws_api_gateway_rest_api" "public_ingress" {
  name = "${var.stack_name}-public-ingress"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-public-ingress"
    }
  )
}

resource "aws_api_gateway_resource" "setup" {
  count       = local.admin_routes_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.public_ingress.id
  parent_id   = aws_api_gateway_rest_api.public_ingress.root_resource_id
  path_part   = "setup"
}

resource "aws_api_gateway_resource" "setup_proxy" {
  count       = local.admin_routes_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.public_ingress.id
  parent_id   = aws_api_gateway_resource.setup[0].id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_resource" "github" {
  rest_api_id = aws_api_gateway_rest_api.public_ingress.id
  parent_id   = aws_api_gateway_rest_api.public_ingress.root_resource_id
  path_part   = "github"
}

resource "aws_api_gateway_resource" "github_webhooks" {
  rest_api_id = aws_api_gateway_rest_api.public_ingress.id
  parent_id   = aws_api_gateway_resource.github.id
  path_part   = "webhooks"
}

resource "aws_api_gateway_resource" "readyz" {
  count       = local.admin_routes_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.public_ingress.id
  parent_id   = aws_api_gateway_rest_api.public_ingress.root_resource_id
  path_part   = "readyz"
}

resource "aws_api_gateway_method" "root" {
  count         = local.admin_routes_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.public_ingress.id
  resource_id   = aws_api_gateway_rest_api.public_ingress.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  count                   = local.admin_routes_enabled ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.public_ingress.id
  resource_id             = aws_api_gateway_rest_api.public_ingress.root_resource_id
  http_method             = aws_api_gateway_method.root[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.github_apps_setup[0].invoke_arn
}

resource "aws_api_gateway_method" "setup" {
  count         = local.admin_routes_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.public_ingress.id
  resource_id   = aws_api_gateway_resource.setup[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "setup" {
  count                   = local.admin_routes_enabled ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.public_ingress.id
  resource_id             = aws_api_gateway_resource.setup[0].id
  http_method             = aws_api_gateway_method.setup[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.github_apps_setup[0].invoke_arn
}

resource "aws_api_gateway_method" "setup_proxy" {
  count         = local.admin_routes_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.public_ingress.id
  resource_id   = aws_api_gateway_resource.setup_proxy[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "setup_proxy" {
  count                   = local.admin_routes_enabled ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.public_ingress.id
  resource_id             = aws_api_gateway_resource.setup_proxy[0].id
  http_method             = aws_api_gateway_method.setup_proxy[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.github_apps_setup[0].invoke_arn
}

resource "aws_api_gateway_method" "github_webhooks" {
  rest_api_id   = aws_api_gateway_rest_api.public_ingress.id
  resource_id   = aws_api_gateway_resource.github_webhooks.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "github_webhooks" {
  rest_api_id             = aws_api_gateway_rest_api.public_ingress.id
  resource_id             = aws_api_gateway_resource.github_webhooks.id
  http_method             = aws_api_gateway_method.github_webhooks.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.public_ingress.invoke_arn
}

resource "aws_api_gateway_method" "readyz" {
  count         = local.admin_routes_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.public_ingress.id
  resource_id   = aws_api_gateway_resource.readyz[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "readyz" {
  count                   = local.admin_routes_enabled ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.public_ingress.id
  resource_id             = aws_api_gateway_resource.readyz[0].id
  http_method             = aws_api_gateway_method.readyz[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.github_apps_setup[0].invoke_arn
}

resource "aws_api_gateway_deployment" "public_ingress" {
  rest_api_id = aws_api_gateway_rest_api.public_ingress.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.github_webhooks.id,
      aws_lambda_function.public_ingress.source_code_hash,
      local.admin_routes_enabled ? aws_api_gateway_integration.root[0].id : "",
      local.admin_routes_enabled ? aws_api_gateway_integration.setup[0].id : "",
      local.admin_routes_enabled ? aws_api_gateway_integration.setup_proxy[0].id : "",
      local.admin_routes_enabled ? aws_api_gateway_integration.readyz[0].id : "",
      local.admin_routes_enabled ? aws_lambda_function.github_apps_setup[0].source_code_hash : "",
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "public_ingress" {
  rest_api_id   = aws_api_gateway_rest_api.public_ingress.id
  deployment_id = aws_api_gateway_deployment.public_ingress.id
  stage_name    = "prod"

  xray_tracing_enabled = false

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-public-ingress-stage"
    }
  )
}

resource "aws_api_gateway_method_settings" "public_ingress" {
  rest_api_id = aws_api_gateway_rest_api.public_ingress.id
  stage_name  = aws_api_gateway_stage.public_ingress.stage_name
  method_path = "*/*"

  settings {
    logging_level   = "OFF"
    metrics_enabled = true
  }
}

resource "aws_lambda_permission" "public_ingress" {
  statement_id  = "AllowAPIGatewayInvokePublicIngress"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.public_ingress.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.public_ingress.id}/*"
}

resource "aws_lambda_permission" "github_apps_setup" {
  count         = local.admin_routes_enabled ? 1 : 0
  statement_id  = "AllowAPIGatewayInvokeGitHubAppsSetup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_apps_setup[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.public_ingress.id}/*"
}

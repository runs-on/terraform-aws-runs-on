resource "aws_cloudwatch_log_group" "cache_credential_broker_lambda" {
  name              = "/aws/lambda/${var.stack_name}-cache-broker"
  retention_in_days = 14

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-cache-broker-lambda"
    }
  )
}

resource "aws_iam_role" "cache_credential_broker" {
  name = "${var.stack_name}-cache-broker-role"

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
    var.tags,
    {
      Name = "${var.stack_name}-cache-broker-role"
    }
  )
}

resource "aws_iam_role_policy" "cache_credential_broker_logs" {
  name = "RunsOnCacheCredentialBrokerLogs"
  role = aws_iam_role.cache_credential_broker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cache_credential_broker_lambda.arn}:*"
    }]
  })
}

resource "aws_iam_role_policy" "cache_credential_broker_assume_runner" {
  name = "RunsOnCacheCredentialBrokerAssumeRunner"
  role = aws_iam_role.cache_credential_broker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Resource = var.compute.runner_iam.role_arn
        Condition = {
          StringEquals = {
            "aws:RequestTag/runs-on-cache-brokered" = "true"
          }
          StringLike = {
            "aws:RequestTag/runs-on-cache-repository" = "*/*"
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "runs-on-cache-brokered",
              "runs-on-cache-repository"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cache_credential_broker_read_jwks" {
  name = "RunsOnCacheCredentialBrokerReadJwks"
  role = aws_iam_role.cache_credential_broker.id

  # The control plane publishes GitHub's OIDC JWKS to this single key
  # (pkg/jwkscache); the broker validates runtime tokens exclusively against
  # it and holds no other S3 permissions.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.extras.cache.bucket_arn}/agents/github-jwks.json"
      }
    ]
  })
}

resource "aws_lambda_function" "cache_credential_broker" {
  function_name = "${var.stack_name}-cache-broker"
  role          = aws_iam_role.cache_credential_broker.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  # Headroom for the caller-identity proof fetch, the S3 JWKS read, and the
  # STS AssumeRole round-trip.
  timeout     = 30
  memory_size = 128

  filename         = "${local.lambda_artifact_dir}/cache-credential-broker.zip"
  source_code_hash = filebase64sha256("${local.lambda_artifact_dir}/cache-credential-broker.zip")

  environment {
    variables = {
      CACHE_BUCKET_ARN      = var.extras.cache.bucket_arn
      RUNNER_ROLE_ARN       = var.compute.runner_iam.role_arn
      GITHUB_ENTERPRISE_URL = local.github_enterprise_url
      GITHUB_TOKEN_ISSUER   = local.github_token_issuer
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-cache-broker"
    }
  )

  depends_on = [
    aws_iam_role_policy.cache_credential_broker_logs,
    aws_iam_role_policy.cache_credential_broker_assume_runner,
    aws_iam_role_policy.cache_credential_broker_read_jwks,
  ]
}

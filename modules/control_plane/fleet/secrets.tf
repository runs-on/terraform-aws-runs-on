data "archive_file" "config_materializer" {
  type        = "zip"
  output_path = "${path.root}/.terraform/runs-on-${substr(sha1(var.stack_name), 0, 8)}-${var.stack_name}-fleet-config-materializer.zip"

  source {
    content  = <<-PY
      import boto3
      from botocore.exceptions import ClientError

      secrets = boto3.client("secretsmanager")


      def handler(event, context):
          secret_id = event["secret_id"]
          secret_string = event["secret_string"]
          client_request_token = event["client_request_token"]

          try:
              response = secrets.put_secret_value(
                  SecretId=secret_id,
                  SecretString=secret_string,
                  ClientRequestToken=client_request_token,
              )
              return {"version_id": response["VersionId"]}
          except ClientError as error:
              if error.response.get("Error", {}).get("Code") == "ResourceExistsException":
                  return {"version_id": client_request_token}
              raise
    PY
    filename = "index.py"
  }
}

resource "aws_cloudwatch_log_group" "config_materializer" {
  name              = "/runs-on/${var.stack_name}/lambda/fleet-config-materializer"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_iam_role" "config_materializer" {
  name = "${var.stack_name}-fleet-config-materializer-role"

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

resource "aws_iam_role_policy" "config_materializer" {
  name = "RunsOnFleetConfigMaterializerPermissions"
  role = aws_iam_role.config_materializer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:PutSecretValue",
        ]
        Resource = aws_secretsmanager_secret.config.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.config_materializer.arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "config_materializer" {
  function_name = "${var.stack_name}-fleet-config-materializer"
  role          = aws_iam_role.config_materializer.arn
  runtime       = "python3.14"
  handler       = "index.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.config_materializer.output_path
  source_code_hash = data.archive_file.config_materializer.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.config_materializer.name
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-fleet-config-materializer"
    }
  )

  depends_on = [
    aws_cloudwatch_log_group.config_materializer,
  ]
}

resource "aws_lambda_invocation" "config_materializer" {
  function_name = aws_lambda_function.config_materializer.function_name
  # Publish after graph values such as same-apply subnet IDs are known, without
  # making Terraform own Secrets Manager staging labels for the Fleet config.
  input = jsonencode({
    secret_id            = aws_secretsmanager_secret.config.arn
    secret_string        = local.config_secret_json
    client_request_token = local.config_secret_version
  })
  triggers = {
    lambda_version       = aws_lambda_function.config_materializer.source_code_hash
    secret_id            = aws_secretsmanager_secret.config.arn
    client_request_token = local.config_secret_version
  }

  depends_on = [
    aws_iam_role_policy.config_materializer,
  ]
}

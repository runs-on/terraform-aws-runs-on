# modules/core/secrets.tf
# Secrets used by App Runner runtime environment

resource "aws_secretsmanager_secret" "runs_on_stack_config" {
  name        = local.stack_config_secret_id
  description = "RunsOn stack configuration for App Runner runtime"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-stack-config"
    }
  )
}

resource "aws_secretsmanager_secret_version" "runs_on_stack_config" {
  secret_id     = aws_secretsmanager_secret.runs_on_stack_config.id
  secret_string = local.stack_config_json
}

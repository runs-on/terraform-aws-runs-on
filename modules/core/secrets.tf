# modules/core/secrets.tf
# Secrets used by App Runner runtime environment

resource "aws_secretsmanager_secret" "runs_on_stack_config" {
  name                    = local.stack_config_secret_id
  description             = "RunsOn stack configuration for App Runner runtime"
  recovery_window_in_days = 0

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

resource "aws_secretsmanager_secret" "runs_on_app_config" {
  count                   = var.app_config_json != "" ? 1 : 0
  name                    = "/runs-on/${var.stack_name}/app-config"
  description             = "RunsOn GitHub App configuration"
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-app-config"
    }
  )
}

resource "aws_secretsmanager_secret_version" "runs_on_app_config" {
  count         = var.app_config_json != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.runs_on_app_config[0].id
  secret_string = var.app_config_json
}

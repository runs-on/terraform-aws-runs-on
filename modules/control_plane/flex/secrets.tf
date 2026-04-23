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

resource "aws_secretsmanager_secret_version" "runs_on_stack_config" {
  secret_id     = aws_secretsmanager_secret.runs_on_stack_config.id
  secret_string = local.stack_config_json
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

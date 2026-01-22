# modules/core/ssm.tf
# SSM Parameter Store resources for sensitive environment variables
# These are used by App Runner via runtime_environment_secrets

###########################
# SSM Parameters for Secrets
###########################

resource "aws_ssm_parameter" "license_key" {
  count = var.license_key != "" ? 1 : 0

  name  = "/${var.stack_name}/secrets/license-key"
  type  = "SecureString"
  value = var.license_key

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-license-key"
    }
  )
}

resource "aws_ssm_parameter" "server_password" {
  count = var.server_password != "" ? 1 : 0

  name  = "/${var.stack_name}/secrets/server-password"
  type  = "SecureString"
  value = var.server_password

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-server-password"
    }
  )
}

resource "aws_ssm_parameter" "integration_step_security_api_key" {
  count = var.integration_step_security_api_key != "" ? 1 : 0

  name  = "/${var.stack_name}/secrets/step-security-api-key"
  type  = "SecureString"
  value = var.integration_step_security_api_key

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-step-security-api-key"
    }
  )
}

resource "aws_ssm_parameter" "otel_exporter_headers" {
  count = var.otel_exporter_headers != "" ? 1 : 0

  name  = "/${var.stack_name}/secrets/otel-exporter-headers"
  type  = "SecureString"
  value = var.otel_exporter_headers

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-otel-exporter-headers"
    }
  )
}

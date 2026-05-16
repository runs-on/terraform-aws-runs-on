# modules/core/ssm.tf
# SSM Parameter Store resources for App Runner runtime secrets

###########################
# SSM Parameters for Secrets
###########################

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

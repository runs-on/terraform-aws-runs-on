# modules/flex_control_plane/ssm.tf
# SSM Parameter Store resources for worker-service runtime secrets

###########################
# SSM Parameters for Secrets
###########################

resource "aws_ssm_parameter" "otel_exporter_headers" {
  count = local.runtime.otel_exporter_headers != "" ? 1 : 0

  name  = "/${var.stack_name}/secrets/otel-exporter-headers"
  type  = "SecureString"
  value = local.runtime.otel_exporter_headers

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-otel-exporter-headers"
    }
  )
}

resource "aws_ssm_parameter" "license_status" {
  name  = local.license_status_parameter_name
  type  = "String"
  value = local.license_status_initial_value

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-license-status"
    }
  )

  lifecycle {
    ignore_changes = [value]
  }
}

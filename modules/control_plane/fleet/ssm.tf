resource "aws_ssm_parameter" "otel_exporter_headers" {
  count = local.runtime.otel_exporter_headers != "" ? 1 : 0

  name  = "/${var.stack_name}/secrets/otel-exporter-headers"
  type  = "SecureString"
  value = local.runtime.otel_exporter_headers

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-otel-exporter-headers"
    }
  )
}

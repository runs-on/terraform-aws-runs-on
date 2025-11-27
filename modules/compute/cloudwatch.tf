# modules/compute/cloudwatch.tf
# CloudWatch resources for EC2 instances

resource "aws_cloudwatch_log_group" "ec2_instances" {
  name              = "${var.log_group_name}/${var.stack_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-ec2-logs"
      Environment = var.environment
    }
  )
}

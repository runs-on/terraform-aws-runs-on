# modules/compute/resource_groups.tf
# EC2 Resource Groups for cost tracking and management

resource "aws_resourcegroups_group" "ec2_instances" {
  name        = "${var.stack_name}-ec2-instances"
  description = "Resource group for RunsOn EC2 instances in ${var.stack_name}"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::EC2::Instance"]
      TagFilters = [
        {
          Key    = var.cost_allocation_tag
          Values = [var.stack_name]
        }
      ]
    })
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ec2-instances"
    }
  )
}

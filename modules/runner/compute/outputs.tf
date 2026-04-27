output "compute" {
  description = "Shared runner compute resources"
  value = {
    runner_iam = {
      role_arn     = aws_iam_role.ec2_instance.arn
      role_name    = aws_iam_role.ec2_instance.name
      role_id      = aws_iam_role.ec2_instance.unique_id
      profile_arn  = aws_iam_instance_profile.ec2.arn
      profile_name = aws_iam_instance_profile.ec2.name
    }
    runner_logs = {
      group_name          = aws_cloudwatch_log_group.ec2_instances.name
      group_arn           = aws_cloudwatch_log_group.ec2_instances.arn
      resource_group_name = aws_resourcegroups_group.ec2_instances.name
      resource_group_arn  = aws_resourcegroups_group.ec2_instances.arn
    }
    launch_templates = {
      linux_default = {
        id             = "${aws_launch_template.linux_default.id}:${aws_launch_template.linux_default.latest_version}"
        latest_version = aws_launch_template.linux_default.latest_version
      }
      linux_default_nested = {
        id             = "${aws_launch_template.linux_default_nested.id}:${aws_launch_template.linux_default_nested.latest_version}"
        latest_version = aws_launch_template.linux_default_nested.latest_version
      }
      windows_default = {
        id             = "${aws_launch_template.windows_default.id}:${aws_launch_template.windows_default.latest_version}"
        latest_version = aws_launch_template.windows_default.latest_version
      }
      windows_default_nested = {
        id             = "${aws_launch_template.windows_default_nested.id}:${aws_launch_template.windows_default_nested.latest_version}"
        latest_version = aws_launch_template.windows_default_nested.latest_version
      }
      linux_private = {
        id             = "${aws_launch_template.linux_private.id}:${aws_launch_template.linux_private.latest_version}"
        latest_version = aws_launch_template.linux_private.latest_version
      }
      linux_private_nested = {
        id             = "${aws_launch_template.linux_private_nested.id}:${aws_launch_template.linux_private_nested.latest_version}"
        latest_version = aws_launch_template.linux_private_nested.latest_version
      }
      windows_private = {
        id             = "${aws_launch_template.windows_private.id}:${aws_launch_template.windows_private.latest_version}"
        latest_version = aws_launch_template.windows_private.latest_version
      }
      windows_private_nested = {
        id             = "${aws_launch_template.windows_private_nested.id}:${aws_launch_template.windows_private_nested.latest_version}"
        latest_version = aws_launch_template.windows_private_nested.latest_version
      }
    }
  }
}

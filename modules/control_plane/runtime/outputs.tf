output "runtime" {
  description = "Runtime ECS resources"
  value = {
    cluster_name        = aws_ecs_cluster.this.name
    cluster_arn         = aws_ecs_cluster.this.arn
    service_name        = aws_ecs_service.this.name
    service_arn         = "arn:aws:ecs:${var.region}:${var.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
    task_definition_arn = aws_ecs_task_definition.this.arn
    log_group_name      = aws_cloudwatch_log_group.this.name
    log_group_arn       = aws_cloudwatch_log_group.this.arn
    execution_role_arn  = aws_iam_role.execution.arn
    execution_role_name = aws_iam_role.execution.name
  }
}

output "task_role" {
  description = "Shared ECS task role used to manage EC2 runners"
  value = {
    arn  = aws_iam_role.task.arn
    id   = aws_iam_role.task.id
    name = aws_iam_role.task.name
  }
}

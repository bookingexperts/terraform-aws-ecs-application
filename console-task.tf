resource "aws_ecs_task_definition" "console" {
  family                = "${var.name}-${local.container_names.console}-${var.env}"
  container_definitions = jsonencode([local.console_container_definition])
  task_role_arn         = aws_iam_role.task-role.arn
  network_mode          = "awsvpc"

  volume {
    host_path = "${var.storage_base_path}/${local.name}"
    name      = "storage"
  }
}

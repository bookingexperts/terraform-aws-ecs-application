output "target_group" {
  value = aws_lb_target_group.web
}

output "task_role" {
  value = aws_iam_role.task-role
}

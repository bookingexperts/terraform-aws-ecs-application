resource "aws_cloudwatch_log_group" "service" {
  name              = local.name
  retention_in_days = var.log_retention
}


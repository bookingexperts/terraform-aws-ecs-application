resource "aws_ecs_task_definition" "worker" {
  family                = "${var.name}-${local.container_names.worker}-${var.env}"
  container_definitions = jsonencode([local.worker_container_definition])
  task_role_arn         = aws_iam_role.task-role.arn
  network_mode          = "awsvpc"

  volume {
    host_path = "${var.storage_base_path}/${local.name}"
    name      = "storage"
  }

  tags = {
    workload-type = var.workload_type
  }
}

resource "aws_ecs_service" "worker" {
  name                               = "${var.name}-worker-${var.env}"
  cluster                            = var.ecs_cluster.arn
  task_definition                    = aws_ecs_task_definition.worker.arn
  desired_count                      = var.worker.count
  deployment_minimum_healthy_percent = var.worker.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.worker.deployment_maximum_percent

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  network_configuration {
    subnets         = var.load_balancers.internal.subnets
    security_groups = [aws_security_group.default.id]
  }

  depends_on = [aws_security_group.default]
}

resource "aws_security_group" "default" {
  name_prefix = "${local.name}-default-"
  vpc_id      = var.vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    workload-type = var.workload_type
  }
}


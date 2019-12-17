resource "aws_ecs_task_definition" "web" {
  family                = "${var.name}-${local.container_names.web}-${var.env}"
  container_definitions = jsonencode([local.web_container_definition])
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

resource "aws_ecs_service" "web" {
  name                               = "${var.name}-web-${var.env}"
  cluster                            = var.ecs_cluster.arn
  task_definition                    = aws_ecs_task_definition.web.arn
  desired_count                      = var.web.count
  deployment_minimum_healthy_percent = var.web.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.web.deployment_maximum_percent

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = local.container_names.web
    container_port   = 8080
  }

  network_configuration {
    subnets         = var.load_balancers.internal.subnets
    security_groups = [aws_security_group.web.id]
  }

  depends_on = [aws_security_group.web]
}

resource "aws_lb_target_group" "web" {
  name_prefix          = "${substr(var.name, 0, 3)}-${substr(var.env, 0, 1)}-"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = var.vpc.id
  target_type          = "ip"
  deregistration_delay = var.web.deregistration_delay
  proxy_protocol_v2    = false

  health_check {
    port                = lookup(var.web.health_check, "port", 8080)
    protocol            = lookup(var.web.health_check, "protocol", "HTTP")
    path                = lookup(var.web.health_check, "path", "/health")
    interval            = lookup(var.web.health_check, "interval", null)
    timeout             = lookup(var.web.health_check, "timeout", null)
    healthy_threshold   = lookup(var.web.health_check, "healthy_threshold", null)
    unhealthy_threshold = lookup(var.web.health_check, "unhealthy_threshold", null)
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    workload-type = var.workload_type
  }
}

resource "aws_security_group" "web" {
  name_prefix = "${local.name}-web-"
  vpc_id      = var.vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    security_groups = var.load_balancers.internal.security_groups
    protocol        = "tcp"
  }

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

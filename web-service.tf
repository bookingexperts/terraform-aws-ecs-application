resource "aws_ecs_task_definition" "web" {
  family                   = "${var.name}-${local.container_names.web}-${var.env}"
  container_definitions    = jsonencode([local.web_container_definition])
  task_role_arn            = aws_iam_role.task-role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = []

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
  desired_count                      = local.auto_scaling.min_web_capacity
  deployment_minimum_healthy_percent = var.web.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.web.deployment_maximum_percent

  capacity_provider_strategy {
    base              = 0
    capacity_provider = "instances"
    weight            = 1
  }

  deployment_controller {
    type = "ECS"
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
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

  dynamic "service_registries" {
    for_each = aws_service_discovery_service.web
    content {
      registry_arn = service_registry.value["arn"]
    }
  }

  depends_on = [aws_security_group.web]

  lifecycle {
    ignore_changes = [desired_count]
  }
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

resource "aws_service_discovery_service" "web" {
  count = var.enable_service_discovery ? 1 : 0
  name = "${var.name}-web-${var.env}"

  dns_config {
    namespace_id = var.service_discovery_namespace.id

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 2
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

resource "aws_appautoscaling_target" "web" {
  count = var.web.auto_scaling != null ? 1 : 0

  max_capacity       = var.web.auto_scaling.max_capacity
  min_capacity       = var.web.auto_scaling.min_capacity
  resource_id        = "service/${var.ecs_cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "web" {
  count = var.web.auto_scaling != null ? 1 : 0

  name               = "Track CPU@${var.web.auto_scaling.target_value}%"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web[0].resource_id
  scalable_dimension = aws_appautoscaling_target.web[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.web[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = var.web.auto_scaling.target_value
  }
}

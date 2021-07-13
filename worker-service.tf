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
  desired_count                      = local.auto_scaling.min_worker_capacity
  deployment_minimum_healthy_percent = var.worker.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.worker.deployment_maximum_percent

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

  network_configuration {
    subnets         = var.load_balancers.internal.subnets
    security_groups = [aws_security_group.default.id]
  }

  lifecycle {
    ignore_changes = [desired_count]
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

resource "aws_appautoscaling_target" "worker" {
  count = var.worker.auto_scaling != null ? 1 : 0

  max_capacity       = var.worker.auto_scaling.max_capacity
  min_capacity       = var.worker.auto_scaling.min_capacity
  resource_id        = "service/${var.ecs_cluster.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker" {
  count = var.worker.auto_scaling != null ? 1 : 0

  name               = "Track CPU@${var.worker.auto_scaling.target_value}% (${coalesce(var.worker.auto_scaling.statistic, "Average")})"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_name = "CPUUtilization"
      namespace   = "AWS/ECS"
      statistic   = coalesce(var.worker.auto_scaling.statistic, "Average")
      unit        = "Percent"

      dimensions {
        name  = "ClusterName"
        value = var.ecs_cluster.name
      }

      dimensions {
        name  = "ServiceName"
        value = aws_ecs_service.worker.name
      }
    }

    target_value = var.worker.auto_scaling.target_value
    scale_in_cooldown  = var.worker.auto_scaling.scale_in_cooldown
    scale_out_cooldown = var.worker.auto_scaling.scale_out_cooldown
  }
}

# resource "aws_appautoscaling_scheduled_action" "min-capacity-worker" {
#   for_each = var.worker.auto_scaling.min_capacity_schedule
# 
#   name               = "Set minimum capacity to ${each.value} at ${each.name}"
#   resource_id        = aws_appautoscaling_target.worker[0].resource_id
#   scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
#   service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
# 
#   scalable_target_action {
#     min_capacity = each.value
#    }
# }
# 

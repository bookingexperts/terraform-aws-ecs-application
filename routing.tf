resource "aws_lb_listener_rule" "wildcard" {
  listener_arn = var.load_balancers.listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    field  = "host-header"
    values = [local.wildcard]
  }
}

resource "aws_lb_listener_rule" "hostname" {
  listener_arn = var.load_balancers.listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    field  = "host-header"
    values = [local.hostname]
  }
}

locals {
  certbot = {
    overrides = {
      add = {
        containerOverrides = [{
          name    = "certbot"
          command = ["be-certbot", "add", local.wildcard]
        }]
      }
      del = {
        containerOverrides = [{
          name    = "certbot"
          command = ["be-certbot", "remove", local.hostname]
        }]
      }
    }
    network_config = {
      awsvpcConfiguration = {
        subnets        = var.load_balancers.internal.subnets
        securityGroups = []
        assignPublicIp = "DISABLED"
      }
    }
  }
}

resource "null_resource" "call-certbot" {
  triggers = {
    hostname = local.hostname
  }

  provisioner "local-exec" {
    command = "aws ecs run-task --region eu-central-1 --cluster ${var.ecs_cluster.name} --task-definition certbot --started-by \"Terraform\" --overrides '${jsonencode(local.certbot.overrides.add)}' --network-configuration '${jsonencode(local.certbot.network_config)}'"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "aws ecs run-task --region eu-central-1 --cluster ${var.ecs_cluster.name} --task-definition certbot --started-by \"Terraform\" --overrides '${jsonencode(local.certbot.overrides.del)}' --network-configuration '${jsonencode(local.certbot.network_config)}'"
  }
}

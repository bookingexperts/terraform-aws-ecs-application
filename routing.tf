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
      containerOverrides = [{
        name    = "certbot"
        command = ["be-certbot", "add", local.wildcard]
      }]
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
    command = <<EOC
      aws ecs run-task --cluster ${var.ecs_cluster.name} --task-definition certbot --started-by "Terraform" \
      --overrides '${jsonencode(local.certbot.overrides)}' --network-configuration '${jsonencode(local.certbot.network_config)}'
EOC
  }
}

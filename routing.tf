resource "aws_lb_listener_rule" "wildcard" {
  listener_arn = var.load_balancers.listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = [local.hostname, local.wildcard]
    }
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
    cluster = var.ecs_cluster.name
    add = jsonencode(local.certbot.overrides.add)
    del = jsonencode(local.certbot.overrides.del)
    network = jsonencode(local.certbot.network_config)
  }

  provisioner "local-exec" {
    command = "aws ecs run-task --region eu-central-1 --cluster ${self.triggers.cluster} --task-definition certbot --started-by \"Terraform\" --overrides '${self.triggers.add}' --network-configuration '${self.triggers.network}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws ecs run-task --region eu-central-1 --cluster ${self.triggers.cluster} --task-definition certbot --started-by \"Terraform\" --overrides '${self.triggers.del}' --network-configuration '${self.triggers.network}'"
  }
}

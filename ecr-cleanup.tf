locals {
  overrides = {
    containerOverrides = [{
      name = "deploy"
      command = ["be", "deploy", "cleanup-images", "--tags", var.env]
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

resource "null_resource" "call-cleanup" {
  triggers = {
    hostname = local.hostname
    cluster  = var.ecs_cluster.name
    command  = jsonencode(local.overrides)
    network  = jsonencode(local.network_config)
    task     = aws_ecs_task_definition.console.arn
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws ecs run-task --region eu-central-1 --cluster ${self.triggers.cluster} --task-definition ${self.triggers.task}  --started-by \"Terraform\" --overrides '${self.triggers.command}' --network-configuration '${self.triggers.network}'"
  }
}


locals {
  env_vars = merge(
    {
      "ASSET_HOST"       = aws_route53_record.cdn.fqdn
      "MEDIA_ASSET_HOST" = aws_route53_record.cdn.fqdn
      "HOST"             = aws_route53_record.hostname.fqdn
      "LOG_NAME"         = local.name
      "AWS_REGION"       = data.aws_region.current.name
      "REDIS_URL"        = "redis://${aws_route53_record.redis.fqdn}:6379"
      "S3_DIRECTORY"     = aws_s3_bucket.media.bucket
      "RDS_HOSTNAME"     = aws_route53_record.rds.fqdn
      "RDS_DB_NAME"      = data.aws_db_instance.db.db_name
      "RDS_PORT"         = tostring(data.aws_db_instance.db.port)
      "RDS_USERNAME"     = data.aws_db_instance.db.master_username
      "RDS_PASSWORD"     = local.rds.password
    },
    var.environment
  )

  base_container_definition = {
    image             = "${var.ecr_repository.repository_url}:${var.env}"
    essential         = true
    cpu               = var.worker.cpu
    memory            = var.worker.memory
    memoryReservation = var.worker.memory / 2
    mountPoints = [{
      containerPath = "/mnt"
      sourceVolume  = "storage"
    }],
    environment = [for name, value in local.env_vars : { "name" = name, "value" = value }]
  }

  console_container_definition = merge(
    local.base_container_definition,
    {
      name  = local.container_names.console
      image = "${var.ecr_repository.repository_url}:${var.env}-next"

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "${local.name}"
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "console"
        }
      }
    }
  )
  web_container_definition = merge(
    local.base_container_definition,
    {
      name              = local.container_names.web
      cpu               = var.web.cpu
      memory            = var.web.memory
      memoryReservation = var.web.memory / 2
      portMappings = [{
        containerPort = 8080
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "${local.name}"
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "web"
        }
      }
    }
  )
  worker_container_definition = merge(
    local.base_container_definition,
    {
      name    = local.container_names.worker
      command = ["sidekiq", "-C", "config/sidekiq.yml"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "${local.name}"
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "worker"
        }
      }
    }
  )
}


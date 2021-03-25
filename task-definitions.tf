locals {
  env_vars = merge(
    {
      "ECS_ENV"          = var.env
      "ASSET_HOST"       = local.cloudfront_host
      "MEDIA_ASSET_HOST" = local.cloudfront_host
      "HOST"             = local.hostname
      "LOG_NAME"         = local.name
      "AWS_REGION"       = data.aws_region.current.name
      "REDIS_URL"        = "redis://${aws_route53_record.redis.fqdn}:6379"
      "S3_DIRECTORY"     = aws_s3_bucket.media.bucket
      "RDS_HOSTNAME"     = local.rds_cname
      "RDS_DB_NAME"      = data.aws_db_instance.db.db_name
      "RDS_PORT"         = tostring(data.aws_db_instance.db.port)
      "RDS_USERNAME"     = data.aws_db_instance.db.master_username
      "RDS_PASSWORD"     = local.rds.password
    },
    var.environment
  )

  base_container_definition = {
    image     = "${var.ecr_repository.repository_url}:${var.env}"
    essential = true
    mountPoints = [{
      containerPath = "/mnt"
      sourceVolume  = "storage"
    }],
    environment = [for name, value in local.env_vars : { "name" = name, "value" = value }]
  }

  console_container_definition = merge(
    local.base_container_definition,
    {
      name              = local.container_names.console
      image             = "${var.ecr_repository.repository_url}:${var.env}-next"
      cpu               = var.worker.cpu / 4
      memoryReservation = var.worker.memory / 4

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.name
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
      volumesFrom       = []
      portMappings = [{
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
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
      name              = local.container_names.worker
      command           = ["sidekiq", "-C", "config/sidekiq.yml", "-c", "4"]
      cpu               = var.worker.cpu
      memory            = var.worker.memory
      memoryReservation = var.worker.memory / 2

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


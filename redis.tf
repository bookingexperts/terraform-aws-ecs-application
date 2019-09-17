locals {
  redis_defaults = {
    node_type            = "cache.t2.micro"
    nodes                = 2
    parameter_group_name = "default.redis5.0"
    engine_version       = "5.0.4"
  }
  redis = merge(local.redis_defaults, var.redis)
}

resource "random_id" "redis" {
  byte_length = 3
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "${regex("^.{0,12}[^-]?", local.name)}-${random_id.redis.hex}"
  replication_group_description = "${local.name} cache cluster"
  engine                        = "redis"
  port                          = 6379
  security_group_ids            = [aws_security_group.redis.id]
  subnet_group_name             = "main"
  snapshot_retention_limit      = 0

  node_type                  = local.redis.node_type
  number_cache_clusters      = local.redis.nodes
  parameter_group_name       = local.redis.parameter_group_name
  engine_version             = local.redis.engine_version
  automatic_failover_enabled = local.redis.nodes > 1
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # Not supported by hiredis driver

  tags = {
    workload-type = var.workload_type
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "redis" {
  name_prefix = "${local.name}-redis-"
  vpc_id      = var.vpc.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    security_groups = [aws_security_group.default.id, aws_security_group.web.id]
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

resource "aws_route53_record" "redis" {
  zone_id = var.route53_zones.internal.zone_id
  name    = "cache.${local.name}.be.internal"
  type    = "CNAME"
  ttl     = 60
  records = [aws_elasticache_replication_group.redis.primary_endpoint_address]
}

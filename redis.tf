locals {
  redis_defaults = {
    node_type            = "cache.t2.micro"
    nodes                = 2
    parameter_group_name = "default.redis5.0"
    engine_version       = "5.0.4"
  }
  redis = merge(local.redis_defaults, var.redis)
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = local.name
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
}

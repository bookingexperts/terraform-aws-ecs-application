locals {
  redis_defaults = {
    node_type            = "cache.t2.micro"
    nodes                = 2
    parameter_group_name = "default.redis5.0"
    engine_version       = "5.0.4"
  }
}

resource "random_string" "redis" {
  for_each = var.redis
  length   = 6
  special  = false

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_elasticache_replication_group" "redis" {
  for_each = { for k, v in var.redis : k => merge(local.redis_defaults, v) }

  replication_group_id          = "${regex("^.{0,12}[^-]?", local.name)}-${regex("^[^-]?.*", random_string.redis[each.key].id)}"
  replication_group_description = "${local.name} ${each.key} cluster"
  engine                        = "redis"
  port                          = 6379
  security_group_ids            = [aws_security_group.redis.id]
  subnet_group_name             = "main"
  snapshot_retention_limit      = 0

  node_type                  = each.value.node_type
  number_cache_clusters      = each.value.nodes
  parameter_group_name       = each.value.parameter_group_name
  engine_version             = each.value.engine_version
  automatic_failover_enabled = each.value.nodes > 1
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # Not supported by hiredis driver
  multi_az_enabled           = each.value.nodes > 1

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
  for_each = var.redis

  zone_id = var.route53_zones.internal.zone_id
  name    = "${each.key}.${local.name}.be.internal"
  type    = "CNAME"
  ttl     = 60
  records = [aws_elasticache_replication_group.redis[each.key].primary_endpoint_address]
}

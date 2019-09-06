locals {
  rds_defaults = {
    db_instance_identifier              = null
    source_db_instance_identifier       = null
    db_snapshot_identifier              = null
    identifier_prefix                   = "${local.name}-"
    engine                              = "postgres"
    engine_version                      = "10.6"
    instance_class                      = "db.t3.medium"
    multi_az                            = false
    backup_retention_period             = 0
    skip_final_snapshot                 = true
    db_subnet_group_name                = "main"
    iam_database_authentication_enabled = true
    vpc_security_group_ids              = ["sg-a10174cb"] # Bastion SG, task related groups are added
    username                            = ""
    password                            = ""
    allocated_storage                   = null
  }
  rds = merge(local.rds_defaults, var.rds)
}

# Optionally create a new DB based on the settings provided in var.rds
data "aws_db_snapshot" "latest" {
  count                  = local.rds.source_db_instance_identifier != null ? 1 : 0
  db_instance_identifier = local.rds.source_db_instance_identifier
  most_recent            = true
}

resource "aws_db_instance" "db" {
  count = local.rds.db_instance_identifier == null ? 1 : 0

  backup_retention_period             = local.rds.backup_retention_period
  db_subnet_group_name                = local.rds.db_subnet_group_name
  engine                              = local.rds.engine
  engine_version                      = local.rds.engine_version
  iam_database_authentication_enabled = local.rds.iam_database_authentication_enabled
  identifier_prefix                   = local.rds.identifier_prefix
  instance_class                      = local.rds.instance_class
  multi_az                            = local.rds.multi_az
  skip_final_snapshot                 = local.rds.skip_final_snapshot
  snapshot_identifier                 = coalesce(data.aws_db_snapshot.latest.0.id, local.rds.db_snapshot_identifier)
  vpc_security_group_ids              = concat(local.rds.vpc_security_group_ids, aws_security_group.rds.*.id)
  password                            = local.rds.password
  username                            = local.rds.username
  allocated_storage                   = local.rds.allocated_storage

  lifecycle {
    create_before_destroy = true
    ignore_changes        = ["snapshot_identifier"]
  }

  tags = {
    workload-type = var.workload_type
  }
}

# Use _data_ for consistent behaviour
data "aws_db_instance" "db" {
  db_instance_identifier = local.rds.db_instance_identifier == null ? aws_db_instance.db.0.identifier : local.rds.db_instance_identifier
}

resource "aws_security_group" "rds" {
  count       = local.rds.db_instance_identifier == null ? 1 : 0
  name_prefix = "${local.name}-rds-"
  vpc_id      = var.vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
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

resource "aws_route53_record" "rds" {
  zone_id = var.route53_zones.internal.zone_id
  name    = "db.${local.name}.be.internal"
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = data.aws_db_instance.db.address
    zone_id                = data.aws_db_instance.db.hosted_zone_id
  }
}

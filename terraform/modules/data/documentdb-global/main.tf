resource "aws_docdb_subnet_group" "this" {
  name        = "${var.environment}-docdb-global-${var.region}"
  description = "Subnet group for DocumentDB Global cluster in ${var.region}"
  subnet_ids  = var.data_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.environment}-docdb-global-subnet-group"
  })
}

resource "aws_docdb_cluster_parameter_group" "this" {
  family      = "docdb5.0"
  name        = "${var.environment}-docdb-global-${var.region}"
  description = "DocumentDB cluster parameter group"

  parameter {
    name  = "tls"
    value = "enabled"
  }

  parameter {
    name  = "audit_logs"
    value = "enabled"
  }

  parameter {
    name  = "profiler"
    value = "enabled"
  }

  parameter {
    name  = "profiler_threshold_ms"
    value = "100"
  }

  tags = var.tags
}

locals {
  cluster_identifier = coalesce(var.cluster_identifier_override, "${var.environment}-docdb-global-${var.region}")
}

resource "aws_docdb_cluster" "this" {
  cluster_identifier        = local.cluster_identifier
  global_cluster_identifier = var.is_primary ? null : var.global_cluster_identifier

  engine         = "docdb"
  engine_version = "5.0.0"

  # Primary cluster needs master credentials (secondary inherits from global cluster)
  master_username = var.is_primary ? "docdb_admin" : null
  master_password = var.is_primary ? "TempPassword123!ChangeMe" : null

  db_subnet_group_name            = aws_docdb_subnet_group.this.name
  db_cluster_parameter_group_name = var.is_primary ? aws_docdb_cluster_parameter_group.this.name : null
  vpc_security_group_ids          = [var.security_group_id]

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  enabled_cloudwatch_logs_exports = var.is_primary ? ["audit", "profiler"] : []

  deletion_protection = true

  backup_retention_period      = var.is_primary ? 35 : 1
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  skip_final_snapshot       = var.is_primary ? false : true
  final_snapshot_identifier = var.is_primary ? "${local.cluster_identifier}-final-snapshot" : null

  tags = merge(var.tags, {
    Name = "${var.environment}-docdb-global-cluster"
  })

  lifecycle {
    ignore_changes = [
      master_password,
      master_username
    ]
  }
}

resource "aws_docdb_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${local.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.this.id

  instance_class = var.instance_class

  tags = merge(var.tags, {
    Name = "${var.environment}-docdb-global-instance-${count.index + 1}"
  })

  lifecycle {
    ignore_changes = [
      auto_minor_version_upgrade
    ]
  }
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.environment}-aurora-global-${var.region}"
  description = "Subnet group for Aurora Global cluster in ${var.region}"
  subnet_ids  = var.data_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.environment}-aurora-global-subnet-group"
  })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier        = "${var.environment}-aurora-global-${var.region}"
  global_cluster_identifier = var.is_primary ? null : var.global_cluster_identifier

  engine                       = "aurora-postgresql"
  engine_version               = "15.8"
  allow_major_version_upgrade  = false

  # Primary cluster uses RDS-managed secrets
  master_username                 = var.is_primary ? "mall_admin" : null
  manage_master_user_password     = var.is_primary ? true : null
  master_user_secret_kms_key_id   = var.is_primary ? var.kms_key_arn : null

  # Secondary cluster configuration
  enable_global_write_forwarding = var.is_primary ? null : var.enable_write_forwarding

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection = true

  skip_final_snapshot = false
  final_snapshot_identifier = "${var.environment}-aurora-global-${var.region}-final-snapshot"

  tags = merge(var.tags, {
    Name = "${var.environment}-aurora-global-cluster"
  })

  lifecycle {
    ignore_changes = [
      replication_source_identifier
    ]
  }
}

resource "aws_rds_cluster_instance" "writer" {
  count = var.is_primary ? 1 : 0

  identifier         = "${var.environment}-aurora-global-${var.region}-writer"
  cluster_identifier = aws_rds_cluster.this.id

  engine         = aws_rds_cluster.this.engine
  engine_version = aws_rds_cluster.this.engine_version

  instance_class = var.writer_instance_class

  db_subnet_group_name = aws_db_subnet_group.this.name

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn

  auto_minor_version_upgrade = false

  tags = merge(var.tags, {
    Name = "${var.environment}-aurora-global-writer"
  })
}

resource "aws_rds_cluster_instance" "readers" {
  count = var.reader_count

  identifier         = "${var.environment}-aurora-global-${var.region}-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id

  engine         = aws_rds_cluster.this.engine
  engine_version = aws_rds_cluster.this.engine_version

  instance_class = var.reader_instance_class

  db_subnet_group_name = aws_db_subnet_group.this.name

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn

  auto_minor_version_upgrade = false

  tags = merge(var.tags, {
    Name = "${var.environment}-aurora-global-reader-${count.index + 1}"
  })
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.environment}-aurora-global-monitoring-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

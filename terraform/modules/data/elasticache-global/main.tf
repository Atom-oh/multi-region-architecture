resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.environment}-elasticache-global-${var.region}"
  description = "Subnet group for ElastiCache Global cluster in ${var.region}"
  subnet_ids  = var.data_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.environment}-elasticache-global-subnet-group"
  })
}

resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.environment}-elasticache-global-${var.region}"
  family = "valkey7"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  tags = var.tags
}

# Primary region creates the global replication group
resource "aws_elasticache_global_replication_group" "this" {
  count = var.is_primary ? 1 : 0

  global_replication_group_id_suffix = "${var.environment}-global"
  primary_replication_group_id       = aws_elasticache_replication_group.this.id

  global_replication_group_description = "Global replication group for ${var.environment}"
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.environment}-elasticache-${var.region}"
  description          = "ElastiCache Global replication group in ${var.region}"

  # For secondary regions, join the global replication group
  global_replication_group_id = var.is_primary ? null : var.global_replication_group_id

  # Primary-only settings
  engine         = var.is_primary ? "valkey" : null
  engine_version = var.is_primary ? "7.2" : null
  node_type      = var.is_primary ? var.node_type : null

  num_node_groups         = var.is_primary ? var.num_node_groups : null
  replicas_per_node_group = var.is_primary ? var.replicas_per_node_group : null

  automatic_failover_enabled = var.is_primary ? true : null
  multi_az_enabled           = var.is_primary ? true : null

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]

  parameter_group_name = var.is_primary ? aws_elasticache_parameter_group.this.name : null

  at_rest_encryption_enabled = var.is_primary ? true : null
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = var.is_primary ? true : null

  snapshot_retention_limit = var.is_primary ? 7 : null
  snapshot_window          = var.is_primary ? "03:00-04:00" : null
  maintenance_window       = var.is_primary ? "sun:04:00-sun:05:00" : null

  auto_minor_version_upgrade = var.is_primary ? false : null

  tags = merge(var.tags, {
    Name = "${var.environment}-elasticache-global"
  })

  lifecycle {
    ignore_changes = [
      automatic_failover_enabled,
      multi_az_enabled,
      num_node_groups,
      replicas_per_node_group,
    ]
  }
}

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

  engine         = var.is_primary ? "valkey" : null
  engine_version = var.is_primary ? "7.2" : null

  node_type = var.is_primary ? var.node_type : null

  num_node_groups         = var.is_primary ? var.num_node_groups : null
  replicas_per_node_group = var.is_primary ? var.replicas_per_node_group : null

  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]

  parameter_group_name = var.is_primary ? aws_elasticache_parameter_group.this.name : null

  at_rest_encryption_enabled = var.is_primary ? true : null
  kms_key_id                 = var.is_primary ? var.kms_key_arn : null
  transit_encryption_enabled = var.is_primary ? true : null

  snapshot_retention_limit = 7
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = false

  tags = merge(var.tags, {
    Name = "${var.environment}-elasticache-global"
  })
}

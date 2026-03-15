# Secrets Manager secrets
resource "aws_secretsmanager_secret" "secrets" {
  for_each = var.secrets

  name        = "${var.environment}/${each.value.name}"
  description = each.value.description
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = 30

  dynamic "replica" {
    for_each = var.is_primary && var.replica_region != "" ? [1] : []
    content {
      region     = var.replica_region
      kms_key_id = var.replica_kms_key_arn != "" ? var.replica_kms_key_arn : null
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${each.value.name}"
    Environment = var.environment
  })
}

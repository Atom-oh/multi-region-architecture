output "replication_group_id" {
  description = "The ID of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.this.id
}

output "primary_endpoint_address" {
  description = "The address of the primary endpoint"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "The address of the reader endpoint"
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "configuration_endpoint_address" {
  description = "The configuration endpoint address for cluster mode"
  value       = aws_elasticache_replication_group.this.configuration_endpoint_address
}

output "global_replication_group_id" {
  description = "The ID of the global replication group (only for primary region)"
  value       = var.is_primary ? aws_elasticache_global_replication_group.this[0].global_replication_group_id : null
}

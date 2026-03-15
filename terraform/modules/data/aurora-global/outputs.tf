output "cluster_id" {
  description = "The RDS Cluster Identifier"
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of the cluster"
  value       = aws_rds_cluster.this.arn
}

output "cluster_endpoint" {
  description = "The cluster endpoint"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "The cluster reader endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = "The database port"
  value       = aws_rds_cluster.this.port
}

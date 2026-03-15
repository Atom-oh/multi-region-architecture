output "cluster_id" {
  description = "The DocumentDB Cluster Identifier"
  value       = aws_docdb_cluster.this.id
}

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of the cluster"
  value       = aws_docdb_cluster.this.arn
}

output "cluster_endpoint" {
  description = "The cluster endpoint"
  value       = aws_docdb_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "The cluster reader endpoint"
  value       = aws_docdb_cluster.this.reader_endpoint
}

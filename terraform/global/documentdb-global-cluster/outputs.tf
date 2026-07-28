output "global_cluster_id" {
  description = "The ID of the DocumentDB global cluster"
  value       = aws_docdb_global_cluster.main.id
}

output "global_cluster_arn" {
  description = "The ARN of the DocumentDB global cluster"
  value       = aws_docdb_global_cluster.main.arn
}

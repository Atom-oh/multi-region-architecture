output "global_cluster_id" {
  description = "The ID of the Aurora global cluster"
  value       = aws_rds_global_cluster.main.id
}

output "global_cluster_arn" {
  description = "The ARN of the Aurora global cluster"
  value       = aws_rds_global_cluster.main.arn
}

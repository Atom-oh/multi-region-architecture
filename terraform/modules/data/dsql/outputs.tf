output "cluster_endpoint" {
  description = "The endpoint of the DSQL cluster"
  value       = "${aws_dsql_cluster.this.identifier}.${var.region}.dsql.amazonaws.com"
}

output "cluster_arn" {
  description = "The ARN of the DSQL cluster"
  value       = aws_dsql_cluster.this.arn
}

output "cluster_identifier" {
  description = "The identifier of the DSQL cluster"
  value       = aws_dsql_cluster.this.identifier
}

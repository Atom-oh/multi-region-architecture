output "alb_security_group_id" {
  description = "The ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "nlb_security_group_id" {
  description = "The ID of the NLB security group (api-gateway)"
  value       = aws_security_group.nlb.id
}

output "eks_node_security_group_id" {
  description = "The ID of the EKS node security group"
  value       = aws_security_group.eks_node.id
}

output "aurora_security_group_id" {
  description = "The ID of the Aurora security group"
  value       = aws_security_group.aurora.id
}

output "documentdb_security_group_id" {
  description = "The ID of the DocumentDB security group"
  value       = aws_security_group.documentdb.id
}

output "elasticache_security_group_id" {
  description = "The ID of the ElastiCache security group"
  value       = aws_security_group.elasticache.id
}

output "msk_security_group_id" {
  description = "The ID of the MSK security group"
  value       = aws_security_group.msk.id
}

output "opensearch_security_group_id" {
  description = "The ID of the OpenSearch security group"
  value       = aws_security_group.opensearch.id
}

output "internal_observability_nlb_security_group_id" {
  description = "The ID of the internal observability NLB security group (ClickHouse, Tempo, Prometheus)"
  value       = aws_security_group.internal_observability_nlb.id
}

output "istio_eastwest_security_group_id" {
  description = "The ID of the Istio ambient east-west gateway security group (az-a <-> az-c cross-cluster mesh)"
  value       = aws_security_group.istio_eastwest.id
}

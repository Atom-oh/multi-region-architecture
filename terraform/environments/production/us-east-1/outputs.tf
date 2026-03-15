output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_id
}

output "aurora_cluster_endpoint" {
  description = "The Aurora cluster endpoint"
  value       = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "The Aurora cluster reader endpoint"
  value       = module.aurora.reader_endpoint
}

output "documentdb_cluster_endpoint" {
  description = "The DocumentDB cluster endpoint"
  value       = module.documentdb.cluster_endpoint
}

output "elasticache_endpoint" {
  description = "The ElastiCache configuration endpoint"
  value       = module.elasticache.configuration_endpoint_address
}

output "elasticache_global_replication_group_id" {
  description = "The ID of the ElastiCache global replication group"
  value       = module.elasticache.global_replication_group_id
}

output "msk_bootstrap_brokers" {
  description = "The MSK bootstrap brokers TLS connection string"
  value       = module.msk.bootstrap_brokers_tls
}

output "msk_cluster_arn" {
  description = "The ARN of the MSK cluster"
  value       = module.msk.cluster_arn
}

output "opensearch_endpoint" {
  description = "The OpenSearch domain endpoint"
  value       = module.opensearch.domain_endpoint
}

output "cloudfront_domain" {
  description = "The CloudFront distribution domain name"
  value       = module.cloudfront.distribution_domain_name
}

output "transit_gateway_id" {
  description = "The ID of the Transit Gateway"
  value       = module.transit_gateway.transit_gateway_id
}

output "s3_static_assets_bucket_arn" {
  description = "The ARN of the static assets S3 bucket"
  value       = module.s3.static_assets_bucket_arn
}

output "s3_replication_role_arn" {
  description = "The ARN of the S3 replication IAM role"
  value       = module.s3.replication_role_arn
}

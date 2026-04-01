# ─────────────────────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "data_subnet_ids" {
  description = "List of data subnet IDs"
  value       = module.vpc.data_subnet_ids
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────────────────────────────────────

output "eks_node_security_group_id" {
  description = "The ID of the EKS node security group"
  value       = module.security_groups.eks_node_security_group_id
}

output "alb_security_group_id" {
  description = "The ID of the ALB security group"
  value       = module.security_groups.alb_security_group_id
}

output "nlb_security_group_id" {
  description = "The ID of the NLB security group"
  value       = module.security_groups.nlb_security_group_id
}

output "internal_observability_nlb_security_group_id" {
  description = "The ID of the internal observability NLB security group (ClickHouse, Tempo, Prometheus)"
  value       = module.security_groups.internal_observability_nlb_security_group_id
}

# ─────────────────────────────────────────────────────────────────────────────
# Data Store Endpoints
# ─────────────────────────────────────────────────────────────────────────────

output "aurora_cluster_endpoint" {
  description = "The Aurora cluster endpoint"
  value       = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "The Aurora cluster reader endpoint"
  value       = module.aurora.reader_endpoint
}

output "aurora_reader_custom_endpoints" {
  description = "AZ-specific custom Aurora reader endpoints"
  value       = module.aurora.reader_custom_endpoints
}

output "elasticache_configuration_endpoint" {
  description = "The ElastiCache configuration endpoint address"
  value       = module.elasticache.configuration_endpoint_address
}

output "msk_bootstrap_brokers" {
  description = "The MSK SASL/SCRAM bootstrap brokers"
  value       = module.msk.bootstrap_brokers_sasl_scram
}

output "msk_cluster_arn" {
  description = "The ARN of the MSK cluster"
  value       = module.msk.cluster_arn
}

output "documentdb_cluster_endpoint" {
  description = "The DocumentDB cluster endpoint"
  value       = module.documentdb.cluster_endpoint
}

output "documentdb_reader_endpoint" {
  description = "The DocumentDB cluster reader endpoint"
  value       = module.documentdb.reader_endpoint
}

output "opensearch_endpoint" {
  description = "The OpenSearch domain endpoint"
  value       = module.opensearch.domain_endpoint
}

# ─────────────────────────────────────────────────────────────────────────────
# KMS
# ─────────────────────────────────────────────────────────────────────────────

output "kms_key_arns" {
  description = "Map of KMS key alias names to their ARNs"
  value       = module.kms.key_arns
}

output "kms_key_ids" {
  description = "Map of KMS key alias names to their IDs"
  value       = module.kms.key_ids
}

# ─────────────────────────────────────────────────────────────────────────────
# S3
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# NLB (Multi-AZ, weighted routing)
# ─────────────────────────────────────────────────────────────────────────────

output "nlb_arn" {
  description = "ARN of the multi-AZ NLB"
  value       = module.nlb.nlb_arn
}

output "nlb_dns_name" {
  description = "DNS name of the multi-AZ NLB"
  value       = module.nlb.nlb_dns_name
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the NLB (for Route53 alias records)"
  value       = module.nlb.nlb_zone_id
}

output "nlb_target_group_arn_az_a" {
  description = "ARN of the AZ-A target group (used by k8s TargetGroupBinding)"
  value       = module.nlb.target_group_arns["az-a"]
}

output "nlb_target_group_arn_az_c" {
  description = "ARN of the AZ-C target group (used by k8s TargetGroupBinding)"
  value       = module.nlb.target_group_arns["az-c"]
}

# ─────────────────────────────────────────────────────────────────────────────
# S3
# ─────────────────────────────────────────────────────────────────────────────

output "s3_static_assets_bucket_arn" {
  description = "The ARN of the static assets S3 bucket"
  value       = module.s3.static_assets_bucket_arn
}

output "s3_static_assets_bucket_domain_name" {
  description = "The bucket domain name of the static assets bucket"
  value       = module.s3.static_assets_bucket_domain_name
}

# Networking
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "data_subnet_ids" {
  value = module.vpc.data_subnet_ids
}

output "transit_gateway_id" {
  value = module.transit_gateway.transit_gateway_id
}

output "transit_gateway_peering_attachment_id" {
  value = module.transit_gateway.peering_attachment_id
}

# Security Groups
output "alb_security_group_id" {
  value = module.security_groups.alb_security_group_id
}

output "nlb_security_group_id" {
  value = module.security_groups.nlb_security_group_id
}

output "documentdb_security_group_id" {
  value = module.security_groups.documentdb_security_group_id
}

output "elasticache_security_group_id" {
  value = module.security_groups.elasticache_security_group_id
}

output "msk_security_group_id" {
  value = module.security_groups.msk_security_group_id
}

output "aurora_security_group_id" {
  value = module.security_groups.aurora_security_group_id
}

output "opensearch_security_group_id" {
  value = module.security_groups.opensearch_security_group_id
}

# KMS
output "kms_key_arns" {
  value = module.kms.key_arns
}

output "kms_key_ids" {
  value = module.kms.key_ids
}

# NLB
output "nlb_dns_name" {
  value = module.nlb.nlb_dns_name
}

output "nlb_zone_id" {
  value = module.nlb.nlb_zone_id
}

output "nlb_target_group_arn" {
  value = module.nlb.target_group_arn
}

# Data Stores
output "dsql_cluster_endpoint" {
  value = module.dsql.cluster_endpoint
}

output "dsql_cluster_arn" {
  value = module.dsql.cluster_arn
}

output "aurora_cluster_endpoint" {
  value = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  value = module.aurora.reader_endpoint
}

output "documentdb_cluster_endpoint" {
  value = module.documentdb.cluster_endpoint
}

output "elasticache_endpoint" {
  value = module.elasticache.configuration_endpoint_address
}

output "msk_bootstrap_brokers" {
  value = module.msk.bootstrap_brokers_tls
}

output "opensearch_endpoint" {
  value = module.opensearch.domain_endpoint
}

# S3
output "s3_static_assets_bucket_arn" {
  value = module.s3.static_assets_bucket_arn
}

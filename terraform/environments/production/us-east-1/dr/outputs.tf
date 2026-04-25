output "dr_sns_topic_arn" {
  value = module.dr_automation.sns_topic_arn
}

output "docdb_failover_lambda_arn" {
  value = module.dr_automation.docdb_failover_lambda_arn
}

output "elasticache_failover_lambda_arn" {
  value = module.dr_automation.elasticache_failover_lambda_arn
}

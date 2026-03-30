output "sns_topic_arn" {
  description = "ARN of the DR alerts SNS topic"
  value       = aws_sns_topic.dr_alerts.arn
}

output "docdb_failover_lambda_arn" {
  description = "ARN of the DocumentDB failover Lambda function"
  value       = aws_lambda_function.docdb_failover.arn
}

output "elasticache_failover_lambda_arn" {
  description = "ARN of the ElastiCache failover Lambda function"
  value       = aws_lambda_function.elasticache_failover.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for health check monitoring"
  value       = aws_cloudwatch_event_rule.health_check_alarm.arn
}

output "docdb_failover_role_arn" {
  description = "ARN of the IAM role for DocumentDB failover Lambda"
  value       = aws_iam_role.docdb_failover.arn
}

output "elasticache_failover_role_arn" {
  description = "ARN of the IAM role for ElastiCache failover Lambda"
  value       = aws_iam_role.elasticache_failover.arn
}

output "log_group_arns" {
  description = "Map of namespace names to their CloudWatch Log Group ARNs"
  value = {
    for namespace, log_group in aws_cloudwatch_log_group.eks_namespaces : namespace => log_group.arn
  }
}

output "alarm_arns" {
  description = "List of CloudWatch Alarm ARNs"
  value = [
    aws_cloudwatch_metric_alarm.high_error_rate.arn,
    aws_cloudwatch_metric_alarm.high_latency.arn,
    aws_cloudwatch_metric_alarm.replication_lag.arn,
    aws_cloudwatch_metric_alarm.kafka_under_replicated.arn
  ]
}

output "sampling_rule_arns" {
  description = "List of X-Ray sampling rule ARNs"
  value = [
    aws_xray_sampling_rule.default.arn,
    aws_xray_sampling_rule.orders.arn,
    aws_xray_sampling_rule.errors.arn
  ]
}

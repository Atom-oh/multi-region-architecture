output "role_arn" {
  description = "ARN of the DSQL access IAM role"
  value       = aws_iam_role.dsql_access.arn
}

output "role_name" {
  description = "Name of the DSQL access IAM role"
  value       = aws_iam_role.dsql_access.name
}

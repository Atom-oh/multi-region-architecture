output "s3_replication_role_arn" {
  description = "The ARN of the S3 replication IAM role"
  value       = length(aws_iam_role.s3_replication) > 0 ? aws_iam_role.s3_replication[0].arn : null
}

output "msk_replicator_role_arn" {
  description = "The ARN of the MSK replicator IAM role"
  value       = aws_iam_role.msk_replicator.arn
}

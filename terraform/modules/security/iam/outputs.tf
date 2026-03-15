output "s3_replication_role_arn" {
  description = "The ARN of the S3 replication IAM role"
  value       = aws_iam_role.s3_replication.arn
}

output "msk_replicator_role_arn" {
  description = "The ARN of the MSK replicator IAM role"
  value       = aws_iam_role.msk_replicator.arn
}

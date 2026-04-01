output "s3_replication_role_arn" {
  description = "The ARN of the S3 replication IAM role"
  value       = length(aws_iam_role.s3_replication) > 0 ? aws_iam_role.s3_replication[0].arn : null
}

output "msk_replicator_role_arn" {
  description = "The ARN of the MSK replicator IAM role"
  value       = aws_iam_role.msk_replicator.arn
}

output "github_actions_role_arn" {
  description = "The ARN of the GitHub Actions OIDC IAM role"
  value       = length(aws_iam_role.github_actions) > 0 ? aws_iam_role.github_actions[0].arn : null
}

output "bedrock_pr_review_profile_arn" {
  description = "The ARN of the Bedrock PR review inference profile"
  value       = length(aws_bedrock_inference_profile.pr_review) > 0 ? aws_bedrock_inference_profile.pr_review[0].arn : null
}

output "bedrock_pr_review_profile_id" {
  description = "The ID of the Bedrock PR review inference profile"
  value       = length(aws_bedrock_inference_profile.pr_review) > 0 ? aws_bedrock_inference_profile.pr_review[0].id : null
}

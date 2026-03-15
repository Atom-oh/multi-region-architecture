output "static_assets_bucket_id" {
  description = "The name of the static assets bucket"
  value       = aws_s3_bucket.static_assets.id
}

output "static_assets_bucket_arn" {
  description = "The ARN of the static assets bucket"
  value       = aws_s3_bucket.static_assets.arn
}

output "static_assets_bucket_domain_name" {
  description = "The bucket domain name of the static assets bucket"
  value       = aws_s3_bucket.static_assets.bucket_domain_name
}

output "analytics_bucket_id" {
  description = "The name of the analytics bucket"
  value       = aws_s3_bucket.analytics.id
}

output "analytics_bucket_arn" {
  description = "The ARN of the analytics bucket"
  value       = aws_s3_bucket.analytics.arn
}

output "replication_role_arn" {
  description = "The ARN of the S3 replication IAM role"
  value       = length(aws_iam_role.replication) > 0 ? aws_iam_role.replication[0].arn : null
}

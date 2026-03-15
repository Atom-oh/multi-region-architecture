output "state_bucket_id" {
  description = "The ID of the S3 bucket storing Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "The ARN of the S3 bucket storing Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "The name of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

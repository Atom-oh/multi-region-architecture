variable "region" {
  description = "AWS region for the S3 bucket and DynamoDB table"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket to store Terraform state files"
  type        = string
  default     = "multi-region-mall-terraform-state"
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "multi-region-mall-terraform-locks"
}

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "environment" {
  description = "Environment name (e.g., prod, staging)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "is_primary" {
  description = "Whether this is the primary region for S3 replication"
  type        = bool
}

variable "static_assets_bucket_name" {
  description = "Name for the static assets bucket"
  type        = string
}

variable "analytics_bucket_name" {
  description = "Name for the analytics data lake bucket"
  type        = string
}

variable "replication_destination_bucket_arn" {
  description = "ARN of the destination bucket for cross-region replication"
  type        = string
  default     = null
}

variable "replication_role_arn" {
  description = "ARN of the IAM role for S3 replication"
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

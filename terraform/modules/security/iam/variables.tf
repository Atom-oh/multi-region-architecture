terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82"
    }
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "source_bucket_arns" {
  description = "List of source S3 bucket ARNs for replication"
  type        = list(string)
  default     = []
}

variable "destination_bucket_arns" {
  description = "List of destination S3 bucket ARNs for replication"
  type        = list(string)
  default     = []
}

variable "create_s3_replication_role" {
  description = "Whether to create the S3 replication role (set to false for secondary regions)"
  type        = bool
  default     = true
}

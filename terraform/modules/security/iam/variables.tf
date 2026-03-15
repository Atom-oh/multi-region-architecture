terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

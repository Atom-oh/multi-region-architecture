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
  description = "Environment name (e.g., prod, staging)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "is_primary" {
  description = "Whether this is the primary region for the global cluster"
  type        = bool
}

variable "global_cluster_identifier" {
  description = "Identifier for the DocumentDB global cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "data_subnet_ids" {
  description = "List of subnet IDs for the database"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the cluster"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  type        = string
}

variable "instance_class" {
  description = "Instance class for DocumentDB instances"
  type        = string
  default     = "db.r6g.2xlarge"
}

variable "instance_count" {
  description = "Number of instances in the cluster"
  type        = number
  default     = 3
}

variable "cluster_identifier_override" {
  description = "Override the auto-generated cluster identifier (e.g., for imported clusters with different naming)"
  type        = string
  default     = null
}

variable "master_password" {
  description = "Master password for the primary DocumentDB cluster"
  type        = string
  sensitive   = true
  default     = null
}

variable "source_region" {
  description = "Source region for secondary cluster (required for cross-region replication)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

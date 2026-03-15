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
  description = "Whether this is the primary region for the global cluster"
  type        = bool
}

variable "global_cluster_identifier" {
  description = "Identifier for the Aurora global cluster"
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

variable "writer_instance_class" {
  description = "Instance class for the writer instance"
  type        = string
  default     = "db.r6g.2xlarge"
}

variable "reader_instance_class" {
  description = "Instance class for reader instances"
  type        = string
  default     = "db.r6g.xlarge"
}

variable "reader_count" {
  description = "Number of reader instances"
  type        = number
  default     = 2
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 35
}

variable "enable_write_forwarding" {
  description = "Enable write forwarding for secondary clusters"
  type        = bool
  default     = true
}

variable "master_password" {
  description = "Master password for the primary Aurora cluster"
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

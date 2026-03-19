terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
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
  description = "Whether this is the primary region for the global datastore"
  type        = bool
}

variable "global_replication_group_id" {
  description = "ID of the global replication group to join (for secondary regions)"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "data_subnet_ids" {
  description = "List of subnet IDs for the cache cluster"
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

variable "node_type" {
  description = "Node type for ElastiCache nodes"
  type        = string
  default     = "cache.r7g.xlarge"
}

variable "num_node_groups" {
  description = "Number of node groups (shards) for cluster mode"
  type        = number
  default     = 3
}

variable "replicas_per_node_group" {
  description = "Number of replica nodes per node group"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

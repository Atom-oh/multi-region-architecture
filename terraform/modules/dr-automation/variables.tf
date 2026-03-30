terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "docdb_global_cluster_id" {
  description = "DocumentDB global cluster identifier"
  type        = string
}

variable "docdb_target_cluster_id" {
  description = "DocumentDB target cluster identifier for failover (secondary region cluster)"
  type        = string
}

variable "elasticache_global_group_id" {
  description = "ElastiCache global replication group identifier"
  type        = string
}

variable "elasticache_target_region" {
  description = "Target region for ElastiCache failover"
  type        = string
}

variable "elasticache_target_group_id" {
  description = "ElastiCache target replication group identifier for failover"
  type        = string
}

variable "notification_email" {
  description = "Email address for DR event notifications"
  type        = string
}

variable "enable_auto_failover" {
  description = "Enable automatic failover (false = manual approval required)"
  type        = bool
  default     = false
}

variable "route53_health_check_ids" {
  description = "List of Route53 health check IDs to monitor"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

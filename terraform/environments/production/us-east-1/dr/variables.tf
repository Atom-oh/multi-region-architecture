variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "docdb_global_cluster_id" {
  description = "DocumentDB global cluster identifier"
  type        = string
}

variable "docdb_target_cluster_id" {
  description = "DocumentDB target cluster identifier for failover"
  type        = string
}

variable "elasticache_target_region" {
  description = "Target region for ElastiCache failover"
  type        = string
  default     = "us-west-2"
}

variable "elasticache_target_group_id" {
  description = "Target ElastiCache replication group ID for failover"
  type        = string
}

variable "notification_email" {
  description = "Email for DR notification"
  type        = string
}

variable "enable_auto_failover" {
  description = "Enable automatic failover (false = manual approval required)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

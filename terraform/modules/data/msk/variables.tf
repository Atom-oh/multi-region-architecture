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

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "data_subnet_ids" {
  description = "List of subnet IDs for the MSK cluster"
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

variable "broker_instance_type" {
  description = "Instance type for Kafka brokers"
  type        = string
  default     = "kafka.m5.2xlarge"
}

variable "number_of_broker_nodes" {
  description = "Number of broker nodes in the cluster"
  type        = number
  default     = 6
}

variable "kafka_version" {
  description = "Kafka version"
  type        = string
  default     = "3.5.1"
}

variable "ebs_volume_size" {
  description = "Size of EBS volume for each broker in GB"
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

variable "enable_replicator" {
  description = "Enable MSK Replicator for cross-region replication"
  type        = bool
  default     = false
}

variable "source_cluster_arn" {
  description = "ARN of the source MSK cluster for replication"
  type        = string
  default     = null
}

variable "target_cluster_arn" {
  description = "ARN of the target MSK cluster for replication"
  type        = string
  default     = null
}

variable "replicator_topics" {
  description = "List of topic patterns to replicate"
  type        = list(string)
  default     = ["orders.*", "payments.*", "catalog.*", "user.*"]
}

variable "default_replication_factor" {
  description = "Default replication factor for topics (must be <= number_of_broker_nodes)"
  type        = number
  default     = 3
}

variable "min_insync_replicas" {
  description = "Minimum in-sync replicas for producer acks (must be < default_replication_factor)"
  type        = number
  default     = 2
}

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
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "Primary AWS region"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for secret encryption"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of secrets to create"
  type = map(object({
    name        = string
    description = string
  }))
  default = {}
}

variable "is_primary" {
  description = "Whether this is the primary region (for replication)"
  type        = bool
  default     = true
}

variable "replica_region" {
  description = "Region for secret replication (if is_primary is true)"
  type        = string
  default     = ""
}

variable "replica_kms_key_arn" {
  description = "ARN of the KMS key in the replica region"
  type        = string
  default     = ""
}

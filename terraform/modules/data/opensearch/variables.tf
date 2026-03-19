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
  description = "VPC ID where the domain will be deployed"
  type        = string
}

variable "data_subnet_ids" {
  description = "List of subnet IDs for the OpenSearch domain"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the domain"
  type        = string
}

variable "master_instance_type" {
  description = "Instance type for dedicated master nodes"
  type        = string
  default     = "r6g.large.search"
}

variable "master_instance_count" {
  description = "Number of dedicated master nodes"
  type        = number
  default     = 3
}

variable "data_instance_type" {
  description = "Instance type for data nodes"
  type        = string
  default     = "r6g.xlarge.search"
}

variable "data_instance_count" {
  description = "Number of data nodes"
  type        = number
  default     = 6
}

variable "ebs_volume_size" {
  description = "Size of EBS volume for each data node in GB"
  type        = number
  default     = 500
}

variable "enable_ultrawarm" {
  description = "Enable UltraWarm storage tier"
  type        = bool
  default     = true
}

variable "warm_instance_type" {
  description = "Instance type for UltraWarm nodes"
  type        = string
  default     = "ultrawarm1.medium.search"
}

variable "warm_count" {
  description = "Number of UltraWarm nodes"
  type        = number
  default     = 2
}

variable "master_password" {
  description = "Master password for OpenSearch admin user"
  type        = string
  sensitive   = true
  default     = "Admin@SecurePass123!"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

variable "create_service_linked_role" {
  description = "Whether to create the OpenSearch service-linked role (only needed once per account)"
  type        = bool
  default     = true
}

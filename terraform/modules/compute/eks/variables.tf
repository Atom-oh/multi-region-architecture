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
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "role_name_suffix" {
  description = "Suffix for IAM role names. Defaults to '-{region}'. Set to empty string for roles without region suffix."
  type        = string
  default     = null
}

variable "bootstrap_node_instance_types" {
  description = "Instance types for bootstrap node group"
  type        = list(string)
  default     = ["m5.large", "m5a.large"]
}

variable "bootstrap_node_desired_size" {
  description = "Desired number of bootstrap nodes"
  type        = number
  default     = 2
}

variable "bootstrap_node_min_size" {
  description = "Minimum number of bootstrap nodes"
  type        = number
  default     = 2
}

variable "bootstrap_node_max_size" {
  description = "Maximum number of bootstrap nodes"
  type        = number
  default     = 3
}

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
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of KMS key for S3 encryption"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of EKS OIDC provider for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of EKS OIDC provider (without https://)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

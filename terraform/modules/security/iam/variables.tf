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
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "source_bucket_arns" {
  description = "List of source S3 bucket ARNs for replication"
  type        = list(string)
  default     = []
}

variable "destination_bucket_arns" {
  description = "List of destination S3 bucket ARNs for replication"
  type        = list(string)
  default     = []
}

variable "create_s3_replication_role" {
  description = "Whether to create the S3 replication role (set to false for secondary regions)"
  type        = bool
  default     = true
}

# ── GitHub Actions ──────────────────────────────────────────────────────────

variable "create_github_actions_role" {
  description = "Whether to create the GitHub Actions OIDC role"
  type        = bool
  default     = false
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "github_org" {
  description = "GitHub organization name for OIDC trust (e.g., Atom-oh)"
  type        = string
  default     = "Atom-oh"
}

variable "ecr_repository_prefix" {
  description = "ECR repository prefix (e.g., shopping-mall)"
  type        = string
  default     = "shopping-mall"
}

variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "multi-region-mall-terraform-state"
}

variable "terraform_lock_table" {
  description = "DynamoDB table name for Terraform lock"
  type        = string
  default     = "multi-region-mall-terraform-lock"
}

variable "bedrock_pr_review_model_id" {
  description = "Bedrock foundation model ID for PR review inference profile"
  type        = string
  default     = "anthropic.claude-sonnet-4-6"
}

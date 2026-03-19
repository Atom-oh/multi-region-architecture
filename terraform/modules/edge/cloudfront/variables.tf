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

variable "domain_name" {
  description = "Primary domain name for the distribution"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
}

variable "static_assets_bucket_domain_name" {
  description = "Regional domain name of the S3 bucket for static assets"
  type        = string
}

variable "static_assets_bucket_id" {
  description = "ID of the S3 bucket for static assets"
  type        = string
}

variable "api_domain_name" {
  description = "Domain name for the API origin (e.g., api-internal.example.com)"
  type        = string
}

variable "waf_web_acl_id" {
  description = "ID of the WAF Web ACL to associate with the distribution"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

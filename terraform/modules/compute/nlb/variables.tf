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

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the NLB target group will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the NLB"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the NLB (CloudFront prefix list restricted)"
  type        = string
}

variable "health_check_path" {
  description = "Path for target group health check"
  type        = string
  default     = "/"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for TLS listener (*.atomai.click)"
  type        = string
}

variable "name_override" {
  description = "Override NLB name (use when auto-generated name exceeds 32 chars)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

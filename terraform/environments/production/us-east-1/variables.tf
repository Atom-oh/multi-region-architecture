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

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "Data subnet CIDRs"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "domain_name" {
  description = "Domain name"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront"
  type        = string
}

variable "docdb_global_cluster_identifier" {
  description = "DocumentDB global cluster identifier"
  type        = string
}

variable "argocd_nlb_dns_name" {
  description = "DNS name of the ArgoCD NLB (from kubectl get svc argocd-server-nlb -n argocd). Empty to skip Route53 record creation."
  type        = string
  default     = ""
}

variable "argocd_nlb_zone_id" {
  description = "Hosted zone ID of the ArgoCD NLB (NLB zone ID for Route53 alias)"
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

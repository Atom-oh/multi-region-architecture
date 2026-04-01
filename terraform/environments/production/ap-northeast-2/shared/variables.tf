variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
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

variable "domain_name" {
  description = "Domain name"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "docdb_global_cluster_identifier" {
  description = "DocumentDB global cluster identifier"
  type        = string
  default     = "multi-region-mall-docdb"
}

variable "eks_az_a_cluster_name" {
  description = "EKS cluster name for AZ-a"
  type        = string
}

variable "eks_az_c_cluster_name" {
  description = "EKS cluster name for AZ-c"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for TLS listener (*.atomai.click)"
  type        = string
}

variable "argocd_nlb_dns_name" {
  description = "DNS name of the ArgoCD NLB (created by K8s LB controller)"
  type        = string
  default     = ""
}

variable "argocd_nlb_zone_id" {
  description = "Hosted zone ID of the ArgoCD NLB"
  type        = string
  default     = ""
}

variable "grafana_nlb_dns_name" {
  description = "DNS name of the Grafana NLB (created by K8s LB controller)"
  type        = string
  default     = ""
}

variable "grafana_nlb_zone_id" {
  description = "Hosted zone ID of the Grafana NLB"
  type        = string
  default     = ""
}

variable "cloudfront_acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 (required for CloudFront)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

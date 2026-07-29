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

variable "mgmt_cluster_security_group_id_override" {
  description = <<-EOT
    Break-glass override for the mgmt cluster SG that both eks-az-{a,c} trust as
    their ArgoCD ingress source. null (default) = each spoke looks the cluster up
    live and applies its guards. Set to an SG ID to keep the ingress rule while
    mgmt is unreachable, or "" to drop the rule entirely.

    It lives in this layer rather than in each spoke on purpose: a per-spoke
    variable lets an operator override one AZ and forget the other, and the two
    clusters sit behind one weighted NLB over one Aurora/DocumentDB primary — so
    split ArgoCD reachability means a schema migration reaches half the fleet.
    One apply here moves both. Both spokes still need their own apply to pick the
    new value up; see the Runbooks in ../README.md.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.mgmt_cluster_security_group_id_override == null || var.mgmt_cluster_security_group_id_override == "" || can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", var.mgmt_cluster_security_group_id_override))
    error_message = "mgmt_cluster_security_group_id_override must be null (look the cluster up), \"\" (drop the ArgoCD ingress rule), or a security group ID like sg-0123456789abcdef0."
  }
}

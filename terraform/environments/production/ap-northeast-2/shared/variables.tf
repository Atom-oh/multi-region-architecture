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

# ─────────────────────────────────────────────────────────────────────────────
# mgmt cluster trust inputs — all four live here, not in the spokes.
#
# Every one of them decides who may reach the workload API servers, and every one
# is releasable from the environment with a TF_VAR_*. As per-spoke variables they
# shared one failure mode: release the guard on az-a, forget az-c, and the two
# clusters behind one weighted NLB over one Aurora/DocumentDB primary end up with
# different ArgoCD reachability — a schema migration reaches half the fleet.
#
# Single-sourcing here removes that. It does NOT make the two spokes converge on
# its own: each still needs its own apply to pick a new value up. What it
# guarantees is that they cannot be asked to trust *different* things.
# ─────────────────────────────────────────────────────────────────────────────

variable "mgmt_cluster_name" {
  description = "Management cluster whose SG both eks-az-{a,c} trust for cross-cluster ArgoCD access. Owned by AWS-Demo-Platform (docs/decisions/ADR-003-eks-mgmt-ownership-handoff.md). Also a trust input on the break-glass path, where the override SG must carry this cluster's ownership tag."
  type        = string
  default     = "mall-apne2-mgmt"
}

variable "expected_mgmt_vpc_id" {
  description = "VPC the mgmt cluster must be in for its SG to be trusted. Empty (default) means this region's shared VPC. Set explicitly only to deliberately release the guard after the external repo legitimately moves mgmt to another VPC."
  type        = string
  default     = ""
}

variable "expected_mgmt_tags" {
  description = "Tags the mgmt cluster must carry to be trusted. Set to {} to release the tag guard (the same escape hatch expected_mgmt_vpc_id gives the VPC guard) — e.g. when the external repo stops stamping them."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Project   = "multi-region-mall"
  }
}

variable "mgmt_cluster_security_group_id_override" {
  description = <<-EOT
    Break-glass override for the mgmt cluster SG that both eks-az-{a,c} trust as
    their ArgoCD ingress source. null (default) = each spoke looks the cluster up
    live and applies its guards. Set to an SG ID to keep the ingress rule while
    mgmt is unreachable, or "" to drop the rule entirely.

    Commit the value to terraform.tfvars rather than passing `-var` during the
    incident: passed on the command line, the next unrelated `terraform apply` in
    this layer silently reverts it to null and erases the released_guards trace
    with it — and this is the foundation layer, so that apply is a routine one.
    See the Runbooks in ../README.md.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.mgmt_cluster_security_group_id_override == null || var.mgmt_cluster_security_group_id_override == "" || can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", var.mgmt_cluster_security_group_id_override))
    error_message = "mgmt_cluster_security_group_id_override must be null (look the cluster up), \"\" (drop the ArgoCD ingress rule), or a security group ID like sg-0123456789abcdef0."
  }
}

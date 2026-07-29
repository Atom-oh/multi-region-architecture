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

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for TLS listener (*.atomai.click) in ap-northeast-2"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

variable "mgmt_cluster_name" {
  description = "Management cluster whose SG is trusted for cross-cluster ArgoCD access. Owned by AWS-Demo-Platform (docs/decisions/ADR-003-eks-mgmt-ownership-handoff.md)."
  type        = string
  default     = "mall-apne2-mgmt"
}

variable "expected_mgmt_vpc_id" {
  description = "VPC the mgmt cluster must be in. Empty (default) means this region's shared VPC. Set explicitly only to deliberately release the guard after the external repo legitimately moves mgmt to another VPC."
  type        = string
  default     = ""
}

variable "expected_mgmt_tags" {
  description = "Tags the mgmt cluster must carry to be trusted. Set to {} to release the tag guard (same escape hatch expected_mgmt_vpc_id gives the VPC guard) — e.g. when the external repo stops stamping them."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Project   = "multi-region-mall"
  }
}

# mgmt_cluster_security_group_id is deliberately NOT a variable here: the
# break-glass value lives in shared/ so one apply moves both spokes together.
# See the Runbooks in ../README.md.

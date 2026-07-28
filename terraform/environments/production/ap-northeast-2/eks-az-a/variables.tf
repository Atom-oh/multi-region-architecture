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
  description = "Management cluster whose SG is trusted for cross-cluster ArgoCD access. Owned by AWS-Demo-Platform (docs/decisions/ADR-003)."
  type        = string
  default     = "mall-apne2-mgmt"
}

variable "expected_mgmt_vpc_id" {
  description = "VPC the mgmt cluster must be in. Empty (default) means this region's shared VPC. Set explicitly only to deliberately release the guard after the external repo legitimately moves mgmt to another VPC."
  type        = string
  default     = ""
}

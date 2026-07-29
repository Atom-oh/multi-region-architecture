variable "shared_vpc_id" {
  description = "VPC of the calling layer's region. The default expected home of the mgmt cluster."
  type        = string
}

variable "mgmt_cluster_name" {
  description = "Management cluster whose SG is trusted for cross-cluster ArgoCD access. Owned by AWS-Demo-Platform (docs/decisions/ADR-003-eks-mgmt-ownership-handoff.md)."
  type        = string
  default     = "mall-apne2-mgmt"
}

variable "default_mgmt_cluster_name" {
  description = "The name a non-released configuration uses. Compared against mgmt_cluster_name to detect a released name guard; only override in tests."
  type        = string
  default     = "mall-apne2-mgmt"
}

variable "expected_mgmt_vpc_id" {
  description = "VPC the mgmt cluster must be in. Empty (default) means shared_vpc_id. Set explicitly only to deliberately release the guard after the external repo legitimately moves mgmt to another VPC."
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

variable "default_mgmt_tags" {
  description = "The tag set a non-released configuration expects. Compared against expected_mgmt_tags to detect a released tag guard; only override in tests."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Project   = "multi-region-mall"
  }
}

variable "mgmt_cluster_security_group_id" {
  description = <<-EOT
    Break-glass override for the mgmt cluster SG. null (default) = look the cluster
    up live and apply the guards. Any non-null value skips the lookup entirely —
    which is the point: the data source is only declared when this is null, so
    `-var mgmt_cluster_security_group_id=sg-...` (or `=""` to drop the cross-cluster
    ingress rule altogether) makes a plan possible while mgmt is unreachable or has
    legitimately moved. A commented-out data block is not a procedure.
  EOT
  type        = string
  default     = null

  # A typo like "sg0abc" or a copy-pasted VPC id would otherwise sail through
  # plan — the value skips the lookup, so nothing else validates it — and only
  # fail at apply when the EKS module hands it to an SG rule.
  validation {
    condition     = var.mgmt_cluster_security_group_id == null || var.mgmt_cluster_security_group_id == "" || can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", var.mgmt_cluster_security_group_id))
    error_message = "mgmt_cluster_security_group_id must be null (look the cluster up), \"\" (drop the ArgoCD ingress rule), or a security group ID like sg-0123456789abcdef0."
  }
}

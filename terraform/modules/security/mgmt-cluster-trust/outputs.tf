output "security_group_id" {
  description = "The mgmt cluster SG to trust as an ArgoCD ingress source, or \"\" when the override deliberately drops the rule."
  value       = local.lookup_cluster ? data.aws_eks_cluster.mgmt[0].vpc_config[0].cluster_security_group_id : try(one(data.aws_security_group.mgmt_override).id, "")
}

output "released_guards" {
  description = "Which mgmt trust guards are released, one entry per released guard, empty when all are engaged."
  value       = local.released_guards
}

output "break_glass_confirm_engaged" {
  description = "Whether break_glass_confirm was true on the last apply. Not part of released_guards (it is not a trust input — it doesn't change who is trusted), but it must be reported SOMEWHERE (round-12 review M2-2, confirmed): a confirm left true after recovery pre-disarms the break_glass_gate for the next override with no signal anywhere. scripts/check-mgmt-guards.sh FAILs on confirm-true-without-override."
  value       = var.break_glass_confirm
}

# Same field set, same encoding as shared/'s mgmt_trust_fingerprint output —
# see the comment there (round-12 review M2-1). Extend both together or the
# comparison reports permanent divergence.
output "mgmt_trust_fingerprint" {
  description = "sha256 over all five mgmt trust inputs as this caller applied them. Equal to shared/'s mgmt_trust_fingerprint exactly when this spoke has picked up every current shared/ trust input."
  value = sha256(jsonencode({
    mgmt_cluster_name         = var.mgmt_cluster_name
    default_mgmt_cluster_name = var.default_mgmt_cluster_name
    expected_mgmt_vpc_id      = var.expected_mgmt_vpc_id
    expected_mgmt_tags        = var.expected_mgmt_tags
    override_set              = var.mgmt_cluster_security_group_id != null
    override_value            = var.mgmt_cluster_security_group_id != null ? var.mgmt_cluster_security_group_id : ""
  }))
}

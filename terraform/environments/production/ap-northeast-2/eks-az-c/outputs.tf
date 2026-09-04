# ─────────────────────────────────────────────────────────────────────────────
# EKS
# ─────────────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "The URL of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_url
}

output "karpenter_role_arn" {
  description = "The ARN of the Karpenter controller IAM role"
  value       = module.eks.karpenter_role_arn
}

output "service_account_role_arns" {
  description = "Map of service names to their IAM role ARNs"
  value       = module.eks.service_account_role_arns
}

output "node_group_role_arn" {
  description = "The ARN of the node group IAM role"
  value       = module.eks.node_group_role_arn
}

# ─────────────────────────────────────────────────────────────────────────────
# ALB
# ─────────────────────────────────────────────────────────────────────────────

output "alb_controller_role_arn" {
  description = "The ARN of the IAM role for AWS Load Balancer Controller"
  value       = module.alb.alb_controller_role_arn
}


# ─────────────────────────────────────────────────────────────────────────────
# mgmt trust boundary
# ─────────────────────────────────────────────────────────────────────────────

output "mgmt_guards_released" {
  description = "Which mgmt trust guards were released on the last apply, one entry per released guard, empty when all are engaged. All four inputs come from shared/, so the two spokes are always asked to trust the same thing — but each still needs its own apply, so this output can legitimately differ between them until both have run. Compare them (../README.md Runbooks). Reflects the *current* state — a later normal apply overwrites it, so reconstructing a past break-glass needs state bucket versioning or CloudTrail."
  value       = module.mgmt_trust.released_guards
}

output "mgmt_trust_security_group_id" {
  description = "The mgmt cluster SG this spoke actually resolved and trusts for ArgoCD ingress. Compared between spokes by scripts/check-mgmt-guards.sh — released_guards alone can read [] on both sides (converged) while the *resolved SG ID itself* diverges, e.g. after an mgmt replace where one spoke hasn't re-applied yet."
  value       = module.mgmt_trust.security_group_id
}

output "break_glass_confirm_engaged" {
  description = "Whether break_glass_confirm was true on this spoke's last apply. Reported so a confirm left true after recovery (which would silently pre-disarm the break-glass gate for the next override) is visible — scripts/check-mgmt-guards.sh FAILs on confirm-true-without-override."
  value       = module.mgmt_trust.break_glass_confirm_engaged
}

output "mgmt_trust_fingerprint" {
  description = "sha256 over all five mgmt trust inputs as this spoke last applied them. Compared 3-way (shared/, az-a, az-c) by scripts/check-mgmt-guards.sh — a mismatch against shared/'s mgmt_trust_fingerprint means this spoke has not re-applied since the last shared/ trust-input change, for ANY of the five inputs (not just the name/override pair the script also checks individually)."
  value       = module.mgmt_trust.mgmt_trust_fingerprint
}

output "security_group_id" {
  description = "The mgmt cluster SG to trust as an ArgoCD ingress source, or \"\" when the override deliberately drops the rule."
  value       = local.lookup_cluster ? data.aws_eks_cluster.mgmt[0].vpc_config[0].cluster_security_group_id : try(one(data.aws_security_group.mgmt_override).id, "")
}

output "released_guards" {
  description = "Which mgmt trust guards are released, one entry per released guard, empty when all are engaged."
  value       = local.released_guards
}

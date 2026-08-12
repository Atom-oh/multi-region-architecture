# ─────────────────────────────────────────────────────────────────────────────
# mgmt cluster trust — resolve the SG that becomes an ingress trust boundary on
# a workload cluster's API server, for cross-cluster ArgoCD access.
#
# The cluster is created by a repo we do not control (AWS-Demo-Platform's
# infra/eks-mgmt — docs/decisions/ADR-003-eks-mgmt-ownership-handoff.md), so a
# name-only lookup would authorize whatever answers to that name.
#
# This lives in a module because both spokes need it identically. It used to be
# ~120 duplicated lines in eks-az-a and eks-az-c; guard drift between the two
# was then invisible in review, which is the wrong failure mode for the thing
# deciding who may reach an API server.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  expected_vpc_id = var.expected_mgmt_vpc_id != "" ? var.expected_mgmt_vpc_id : var.shared_vpc_id

  lookup_cluster = var.mgmt_cluster_security_group_id == null

  # Every guard has a release, and all of them are reachable from CI with a
  # TF_VAR_* environment variable — no code change, no review trace. Collecting
  # them here is what makes a released guard visible in a plan and in state.
  # mgmt_cluster_name is in the list because it is *also* a trust input: the
  # override path asserts the SG carries aws:eks:cluster-name = this value, so
  # TF_VAR_mgmt_cluster_security_group_id + TF_VAR_mgmt_cluster_name together
  # would otherwise authorize some other cluster's SG silently.
  released_guards = compact([
    local.lookup_cluster ? "" : "mgmt_cluster_security_group_id=${var.mgmt_cluster_security_group_id == "" ? "\"\" (ArgoCD ingress rule dropped, cluster not looked up or verified)" : var.mgmt_cluster_security_group_id} (cluster lookup and its postconditions skipped)",
    var.mgmt_cluster_name == var.default_mgmt_cluster_name ? "" : "mgmt_cluster_name=${var.mgmt_cluster_name} (trusting a cluster other than ${var.default_mgmt_cluster_name})",
    var.expected_mgmt_vpc_id == "" ? "" : "expected_mgmt_vpc_id=${var.expected_mgmt_vpc_id} (mgmt trusted outside the shared VPC of this region)",
    var.expected_mgmt_tags == var.default_mgmt_tags ? "" : "expected_mgmt_tags=${jsonencode(var.expected_mgmt_tags)} (provisioning-tag guard widened or dropped)",
  ])

  # round-9 added an entry here comparing default_mgmt_cluster_name against the
  # module's own hardcoded "mall-apne2-mgmt" literal, meant to catch someone
  # moving mgmt_cluster_name and default_mgmt_cluster_name to the same new value
  # in one shot (bypassing the name guard instead of completing a real rename).
  # round-10 review MAJOR, confirmed: that entry can't tell the two apart,
  # because after a *legitimate* completed rename (the runbook's step 2) the
  # state looks identical — both variables permanently equal the new name —
  # so it flagged every legitimate rename as permanently "released" forever
  # after, which is strictly worse than not checking at all (an operator
  # running a supported, documented procedure gets an unrecoverable FAIL from
  # here on, exactly the "released signal becomes noise" failure this guard
  # system exists to avoid). There is no state-only fix: distinguishing "both
  # values were set in the same apply" from "set in two applies per the
  # runbook" needs an audit trail Terraform state doesn't carry (CloudTrail on
  # the shared/ apply, or a required-review gate on shared/tfvars changes) —
  # removed rather than kept broken. mgmt_cluster_name == default_mgmt_cluster_name
  # (above) is still the guard for the case it can actually detect: one of the
  # two changed without the other.
}

data "aws_eks_cluster" "mgmt" {
  # count, not an unconditional lookup: a declared data source is refreshed and
  # its postconditions evaluated on every plan, so with mgmt deleted or moved
  # there would be no way to plan the caller short of editing .tf mid-incident.
  count = local.lookup_cluster ? 1 : 0

  name = var.mgmt_cluster_name

  lifecycle {
    postcondition {
      condition     = try(self.vpc_config[0].vpc_id, "") == local.expected_vpc_id
      error_message = "${var.mgmt_cluster_name} is in VPC ${try(self.vpc_config[0].vpc_id, "<none reported>")}, not ${local.expected_vpc_id} — refusing to trust its cluster SG. Set expected_mgmt_vpc_id if the move was intentional."
    }
    postcondition {
      condition     = alltrue([for k, v in var.expected_mgmt_tags : try(self.tags[k], "") == v])
      error_message = "${var.mgmt_cluster_name} does not carry the expected tags (${jsonencode(var.expected_mgmt_tags)}) this platform stamps on its clusters — it may not be the cluster we think it is. Set expected_mgmt_tags = {} to release this guard."
    }
    postcondition {
      # Empty means the caller's EKS module silently drops the cross-cluster
      # ingress rule and ArgoCD's sync fails at runtime instead of at plan time.
      condition     = try(self.vpc_config[0].cluster_security_group_id, "") != ""
      error_message = "${var.mgmt_cluster_name} reported no cluster security group — it is probably still being created. Retry once it is ACTIVE."
    }
    postcondition {
      # A DELETING or FAILED cluster still answers DescribeCluster and still has
      # an SG, so without this the spokes would keep trusting a cluster on its
      # way out. UPDATING is allowed on purpose: a control-plane upgrade reports
      # it for 10-40 minutes without changing the cluster SG, so rejecting it
      # would fail every plan here during routine external maintenance and push
      # operators onto the break-glass path — noise in released_guards.
      condition     = contains(["ACTIVE", "UPDATING"], try(self.status, ""))
      error_message = "${var.mgmt_cluster_name} is ${try(self.status, "in an unknown state")}, not ACTIVE or UPDATING — refusing to trust the SG of a cluster that is being created or torn down."
    }
  }
}

# The override skips the cluster lookup, but the value still has to name a real
# SG of that cluster. DescribeSecurityGroups answers whether or not the cluster
# still exists, which is the whole point of the override, so this costs the
# break-glass path nothing. "" (drop the rule) reads nothing.
data "aws_security_group" "mgmt_override" {
  count = !local.lookup_cluster && var.mgmt_cluster_security_group_id != "" ? 1 : 0

  id = var.mgmt_cluster_security_group_id

  lifecycle {
    postcondition {
      # shared_vpc_id, NOT local.expected_vpc_id (round-9 review MAJOR, confirmed):
      # expected_mgmt_vpc_id and this override are two independent trust inputs
      # that both live in shared/ and are both releasable with their own TF_VAR_*.
      # Anchoring the override to the *releasable* expected_vpc_id meant a single
      # shared/ edit that widened expected_mgmt_vpc_id also silently widened what
      # the override path would accept — one flag defeating both asserts at once.
      # The override is a temporary, manually-named SG for an active incident, not
      # a permanent relocation declaration; it stays anchored to this region's real
      # shared VPC regardless of expected_mgmt_vpc_id. A legitimate permanent
      # relocation still works via the live-lookup path (which does honour
      # expected_mgmt_vpc_id) — this only changes what the *override* accepts.
      condition     = self.vpc_id == var.shared_vpc_id
      error_message = "mgmt_cluster_security_group_id=${var.mgmt_cluster_security_group_id} is in VPC ${self.vpc_id}, not ${var.shared_vpc_id} — an SG from another VPC cannot be an ingress source here anyway. The override always requires this region's shared VPC, even if expected_mgmt_vpc_id was released for the live-lookup path; use \"\" to drop the ArgoCD ingress rule instead."
    }
    postcondition {
      # VPC membership alone is not much of a guard: every ALB/NLB/app/data-layer
      # SG in the region shares that VPC, so without this the override could name
      # any of them as an ingress source on the workload API servers. EKS stamps
      # ownership tags on the SG it manages for a cluster, so asserting one
      # narrows the override to "a security group of the mgmt cluster" at no cost
      # to break-glass.
      #
      # kubernetes.io/cluster/<name>, NOT aws:eks:cluster-name — which EKS also
      # stamps and which reads better, but which is unusable here: the AWS
      # provider strips `aws:`-prefixed system tags out of every data source's
      # `tags` map, so `self.tags["aws:eks:cluster-name"]` is always absent and
      # this assert would have failed for *every* SG. Measured against the live
      # mgmt cluster SG on provider 6.52.0: DescribeSecurityGroups returns four
      # tags including aws:eks:cluster-name, Terraform surfaces three and drops
      # exactly that one. So the guard would have fired only in the incident it
      # exists to survive.
      condition     = try(self.tags["kubernetes.io/cluster/${var.mgmt_cluster_name}"], "") == "owned"
      error_message = "mgmt_cluster_security_group_id=${var.mgmt_cluster_security_group_id} does not carry kubernetes.io/cluster/${var.mgmt_cluster_name}=owned — it is some other SG in the VPC, not a security group EKS manages for ${var.mgmt_cluster_name}. Use \"\" to drop the ArgoCD ingress rule instead of naming an unrelated SG."
    }
  }
}

# A check block is the only construct that reports on a plan without failing it,
# so a plan with any guard released says so out loud instead of looking identical
# to a guarded one. All guards share one assert deliberately: the operator needs
# to know that *something* was released, and the message names which.
check "mgmt_guards_engaged" {
  assert {
    condition     = length(local.released_guards) == 0
    error_message = "GUARDS RELEASED for ${var.mgmt_cluster_name}: ${join("; ", local.released_guards)}. Expected only during a mgmt outage or a deliberate mgmt relocation — restore the defaults once it is over."
  }
}

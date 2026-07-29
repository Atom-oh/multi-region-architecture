terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.environment
      Region      = var.region
      ManagedBy   = "terraform"
      Project     = "multi-region-mall"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Remote State — shared layer (VPC, SGs, data stores)
# ─────────────────────────────────────────────────────────────────────────────

data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "multi-region-mall-terraform-state"
    key    = "production/ap-northeast-2/shared/terraform.tfstate"
    region = "us-east-1"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Management cluster SG (cross-cluster ArgoCD access).
# Looked up directly from the live EKS cluster, NOT from the eks-mgmt remote
# state — that state is owned by the AWS-Demo-Platform repo, and we don't want a
# cross-repo state dependency here. Requires eks:DescribeCluster on mall-apne2-mgmt.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Empty var = this region's shared VPC. Overriding it is the deliberate escape
  # hatch for when AWS-Demo-Platform legitimately rebuilds mgmt elsewhere —
  # without it the guard below would be an unfixable-from-here plan failure.
  expected_mgmt_vpc_id = var.expected_mgmt_vpc_id != "" ? var.expected_mgmt_vpc_id : data.terraform_remote_state.shared.outputs.vpc_id

  mgmt_lookup = var.mgmt_cluster_security_group_id == null
  # The one() indirection is load-bearing: referencing the override data source makes
  # its VPC precondition a dependency of the value the EKS module consumes. Reading
  # var directly would let the plan proceed while the assert was still unevaluated.
  mgmt_sg_id = local.mgmt_lookup ? data.aws_eks_cluster.mgmt[0].vpc_config[0].cluster_security_group_id : try(one(data.aws_security_group.mgmt_override).id, "")
}

data "aws_eks_cluster" "mgmt" {
  # count, not an unconditional lookup: a declared data source is refreshed and
  # its postconditions evaluated on every plan, so with mgmt deleted or moved
  # there would be no way to plan this layer short of editing this file mid-
  # incident. Setting mgmt_cluster_security_group_id removes the read.
  count = local.mgmt_lookup ? 1 : 0

  name = var.mgmt_cluster_name

  # The SG below becomes an ingress trust boundary on this cluster's API server,
  # and the cluster it comes from is created by a repo we don't control. A
  # name-only lookup would authorize whatever happens to answer to that name, so
  # assert the VPC, our provisioning tags, and that the SG actually exists.
  lifecycle {
    postcondition {
      condition     = try(self.vpc_config[0].vpc_id, "") == local.expected_mgmt_vpc_id
      error_message = "${var.mgmt_cluster_name} is in VPC ${try(self.vpc_config[0].vpc_id, "<none reported>")}, not ${local.expected_mgmt_vpc_id} — refusing to trust its cluster SG. Set expected_mgmt_vpc_id if the move was intentional."
    }
    postcondition {
      condition     = alltrue([for k, v in var.expected_mgmt_tags : try(self.tags[k], "") == v])
      error_message = "${var.mgmt_cluster_name} does not carry the expected tags (${jsonencode(var.expected_mgmt_tags)}) this platform stamps on its clusters — it may not be the cluster we think it is. Set expected_mgmt_tags = {} to release this guard."
    }
    postcondition {
      # Empty means the module below silently drops the cross-cluster ingress
      # rule and ArgoCD's sync fails at runtime instead of at plan time.
      condition     = try(self.vpc_config[0].cluster_security_group_id, "") != ""
      error_message = "${var.mgmt_cluster_name} reported no cluster security group — it is probably still being created. Retry once it is ACTIVE."
    }
    postcondition {
      # A DELETING or FAILED cluster still answers DescribeCluster and still has an
      # SG, so without this the spokes would keep trusting a cluster on its way out.
      condition     = try(self.status, "") == "ACTIVE"
      error_message = "${var.mgmt_cluster_name} is ${try(self.status, "in an unknown state")}, not ACTIVE — refusing to trust the SG of a cluster that is being created or torn down."
    }
  }
}

# M-2: the override skips the cluster lookup, but the value still has to name a real
# SG in this region's shared VPC. That keeps `TF_VAR_mgmt_cluster_security_group_id`
# from injecting an arbitrary account SG as an ingress source on the workload API
# servers, and it costs the break-glass path nothing — DescribeSecurityGroups answers
# whether or not the mgmt cluster still exists, which is the whole point of the
# override. "" (drop the rule) reads nothing.
data "aws_security_group" "mgmt_override" {
  count = !local.mgmt_lookup && var.mgmt_cluster_security_group_id != "" ? 1 : 0

  id = var.mgmt_cluster_security_group_id

  lifecycle {
    postcondition {
      condition     = self.vpc_id == data.terraform_remote_state.shared.outputs.vpc_id
      error_message = "mgmt_cluster_security_group_id=${var.mgmt_cluster_security_group_id} is in VPC ${self.vpc_id}, not this region's shared VPC — an SG from another VPC cannot be an ingress source here anyway. Use \"\" to drop the ArgoCD ingress rule instead."
    }
  }
}

# The break-glass override releases all three guards above at once, and it can be
# set from CI with nothing but TF_VAR_mgmt_cluster_security_group_id — no code
# change, no review trace. A check block is the only construct that reports on a
# plan without failing it, so a released-guards plan says so out loud instead of
# looking identical to a guarded one.
check "mgmt_guards_engaged" {
  assert {
    condition = local.mgmt_lookup
    # No coalesce() here: it skips empty strings as well as nulls and errors when
    # every argument is empty, which is precisely the `-var ...=''` break-glass
    # path — the check meant to warn would have hard-failed the plan instead.
    error_message = "GUARDS RELEASED: mgmt_cluster_security_group_id is set (${var.mgmt_cluster_security_group_id == "" ? "empty — ArgoCD ingress rule dropped" : var.mgmt_cluster_security_group_id}), so ${var.mgmt_cluster_name} is not being looked up or verified. Expected only during a mgmt outage — unset it once mgmt is back."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute — EKS (AZ-C only: ap-northeast-2c)
# ─────────────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../../../modules/compute/eks"

  environment                   = var.environment
  region                        = var.region
  cluster_name                  = "mall-apne2-az-c"
  vpc_id                        = data.terraform_remote_state.shared.outputs.vpc_id
  private_subnet_ids            = data.terraform_remote_state.shared.outputs.private_subnet_ids
  alb_security_group_id         = data.terraform_remote_state.shared.outputs.alb_security_group_id
  nlb_security_group_id         = data.terraform_remote_state.shared.outputs.nlb_security_group_id
  argocd_security_group_id      = local.mgmt_sg_id
  bootstrap_node_instance_types = ["t3.medium", "t3a.medium"]
  role_name_suffix              = "-apne2-az-c"
  tags                          = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute — ALB Controller IRSA
# ─────────────────────────────────────────────────────────────────────────────

module "alb" {
  source = "../../../../modules/compute/alb"

  environment       = var.environment
  cluster_name      = "mall-apne2-az-c"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = data.terraform_remote_state.shared.outputs.vpc_id
  role_name_suffix  = "-apne2-az-c"
  tags              = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability — OTel Collector IRSA
# ─────────────────────────────────────────────────────────────────────────────

module "otel_collector_irsa" {
  source = "../../../../modules/observability/otel-collector-irsa"

  environment       = var.environment
  region            = var.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  name_suffix       = "-az-c"
  tags              = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability — Tempo storage (S3 + IRSA)
# ─────────────────────────────────────────────────────────────────────────────

module "tempo_storage" {
  source = "../../../../modules/observability/tempo-storage"

  environment       = var.environment
  region            = var.region
  kms_key_arn       = data.terraform_remote_state.shared.outputs.kms_key_arns["s3"]
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  name_suffix       = "-az-c"
  tags              = var.tags
}

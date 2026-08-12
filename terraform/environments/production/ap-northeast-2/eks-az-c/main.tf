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
# cross-repo state dependency here. Requires eks:DescribeCluster on the cluster.
#
# The guards, the break-glass override, and the released-guard reporting all live
# in the module: both spokes need them character-for-character identically, and
# duplicated guard code makes drift between the two AZs invisible in review.
# ─────────────────────────────────────────────────────────────────────────────

module "mgmt_trust" {
  source = "../../../../modules/security/mgmt-cluster-trust"

  shared_vpc_id = data.terraform_remote_state.shared.outputs.vpc_id

  # All five trust inputs come from shared/, none are per-spoke variables. Each
  # of them decides who may reach this API server, and each is releasable with a
  # TF_VAR_*; as spoke variables they could be released on one AZ and forgotten
  # on the other, leaving the two clusters behind one weighted NLB with different
  # ArgoCD reachability.
  #
  # No try()/fallback here (round-9 review MAJOR, confirmed against diff): a
  # hardcoded default silently absorbs a missing/renamed shared/ output instead
  # of failing the plan, which defeats single-sourcing for exactly the case it
  # exists to guard — e.g. default_mgmt_cluster_name falling back to the module's
  # own "mall-apne2-mgmt" literal would resurrect the "rename guard permanently
  # released" bug round-8 closed. shared/ now ships these outputs unconditionally
  # (it is applied in the same change), so a missing output means shared/ has not
  # been applied yet — fail closed on that plan, not silently trust a default.
  mgmt_cluster_name         = data.terraform_remote_state.shared.outputs.mgmt_cluster_name
  default_mgmt_cluster_name = data.terraform_remote_state.shared.outputs.default_mgmt_cluster_name
  expected_mgmt_vpc_id      = data.terraform_remote_state.shared.outputs.expected_mgmt_vpc_id
  expected_mgmt_tags        = data.terraform_remote_state.shared.outputs.expected_mgmt_tags

  # Reconstructed from two never-null outputs, not read directly (round-10
  # review CRITICAL, confirmed): shared/'s override output can't be exposed as
  # a single nullable value — see the comment on those two outputs in
  # shared/outputs.tf for why a null root output breaks this exact read.
  mgmt_cluster_security_group_id = data.terraform_remote_state.shared.outputs.mgmt_cluster_security_group_id_override_set ? (
    data.terraform_remote_state.shared.outputs.mgmt_cluster_security_group_id_override_value
  ) : null
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
  argocd_security_group_id      = module.mgmt_trust.security_group_id
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

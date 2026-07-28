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
}

data "aws_eks_cluster" "mgmt" {
  name = var.mgmt_cluster_name

  # The SG below becomes an ingress trust boundary on this cluster's API server,
  # and the cluster it comes from is created by a repo we don't control. A
  # name-only lookup would authorize whatever happens to answer to that name, so
  # assert both the VPC and our own provisioning tags before trusting it.
  lifecycle {
    postcondition {
      condition     = self.vpc_config[0].vpc_id == local.expected_mgmt_vpc_id
      error_message = "${var.mgmt_cluster_name} is in VPC ${self.vpc_config[0].vpc_id}, not ${local.expected_mgmt_vpc_id} — refusing to trust its cluster SG. Set expected_mgmt_vpc_id if the move was intentional."
    }
    postcondition {
      condition     = try(self.tags["ManagedBy"], "") == "terraform" && try(self.tags["Project"], "") == "multi-region-mall"
      error_message = "${var.mgmt_cluster_name} is missing the ManagedBy=terraform / Project=multi-region-mall tags this platform stamps on its clusters — it may not be the cluster we think it is."
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute — EKS (AZ-A only: ap-northeast-2a)
# ─────────────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../../../modules/compute/eks"

  environment                   = var.environment
  region                        = var.region
  cluster_name                  = "mall-apne2-az-a"
  vpc_id                        = data.terraform_remote_state.shared.outputs.vpc_id
  private_subnet_ids            = data.terraform_remote_state.shared.outputs.private_subnet_ids
  alb_security_group_id         = data.terraform_remote_state.shared.outputs.alb_security_group_id
  nlb_security_group_id         = data.terraform_remote_state.shared.outputs.nlb_security_group_id
  argocd_security_group_id      = data.aws_eks_cluster.mgmt.vpc_config[0].cluster_security_group_id
  bootstrap_node_instance_types = ["t3.medium", "t3a.medium"]
  role_name_suffix              = "-apne2-az-a"
  tags                          = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute — ALB Controller IRSA
# ─────────────────────────────────────────────────────────────────────────────

module "alb" {
  source = "../../../../modules/compute/alb"

  environment       = var.environment
  cluster_name      = "mall-apne2-az-a"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = data.terraform_remote_state.shared.outputs.vpc_id
  role_name_suffix  = "-apne2-az-a"
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
  name_suffix       = "-az-a"
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
  name_suffix       = "-az-a"
  tags              = var.tags
}

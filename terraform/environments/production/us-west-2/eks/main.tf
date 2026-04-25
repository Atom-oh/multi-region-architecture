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

# Read shared layer state
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "multi-region-mall-terraform-state"
    key    = "production/us-west-2/shared/terraform.tfstate"
    region = "us-east-1"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster
# ─────────────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../../../modules/compute/eks"

  environment                   = var.environment
  region                        = var.region
  cluster_name                  = var.eks_cluster_name
  vpc_id                        = data.terraform_remote_state.shared.outputs.vpc_id
  private_subnet_ids            = data.terraform_remote_state.shared.outputs.private_subnet_ids
  alb_security_group_id         = data.terraform_remote_state.shared.outputs.alb_security_group_id
  nlb_security_group_id         = data.terraform_remote_state.shared.outputs.nlb_security_group_id
  bootstrap_node_instance_types = ["t3.medium", "t3a.medium"]
  tags                          = var.tags

  addon_versions = {
    vpc_cni                = "v1.21.1-eksbuild.3"
    coredns                = "v1.13.2-eksbuild.1"
    kube_proxy             = "v1.35.0-eksbuild.2"
    ebs_csi_driver         = "v1.56.0-eksbuild.1"
    efs_csi_driver         = "v2.3.0-eksbuild.2"
    eks_pod_identity_agent = "v1.3.7-eksbuild.2"
  }
}

module "alb" {
  source = "../../../../modules/compute/alb"

  environment       = var.environment
  cluster_name      = var.eks_cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = data.terraform_remote_state.shared.outputs.vpc_id
  role_name_suffix  = "-us-west-2"
  tags              = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# IRSA Roles (require EKS OIDC provider)
# ─────────────────────────────────────────────────────────────────────────────

module "dsql_irsa" {
  source = "../../../../modules/data/dsql-irsa"

  environment       = var.environment
  region            = var.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  dsql_cluster_arn  = data.terraform_remote_state.shared.outputs.dsql_cluster_arn
  tags              = var.tags
}

module "tempo_storage" {
  source = "../../../../modules/observability/tempo-storage"

  environment       = var.environment
  region            = var.region
  kms_key_arn       = data.terraform_remote_state.shared.outputs.kms_key_arns["s3"]
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags
}

module "otel_collector_irsa" {
  source = "../../../../modules/observability/otel-collector-irsa"

  environment       = var.environment
  region            = var.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────────────────────

module "cloudwatch" {
  source = "../../../../modules/observability/cloudwatch"

  environment      = var.environment
  region           = var.region
  eks_cluster_name = var.eks_cluster_name
  sns_topic_arn    = var.sns_topic_arn
  tags             = var.tags
}

module "xray" {
  source = "../../../../modules/observability/xray"

  environment = var.environment
  tags        = var.tags
}

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
# Compute — EKS (AZ-C only: ap-northeast-2c)
# ─────────────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../../../modules/compute/eks"

  environment                  = var.environment
  region                       = var.region
  cluster_name                 = "mall-apne2-az-c"
  vpc_id                       = data.terraform_remote_state.shared.outputs.vpc_id
  private_subnet_ids           = data.terraform_remote_state.shared.outputs.private_subnet_ids
  alb_security_group_id        = data.terraform_remote_state.shared.outputs.alb_security_group_id
  nlb_security_group_id        = data.terraform_remote_state.shared.outputs.nlb_security_group_id
  bootstrap_node_instance_types = ["t3.medium", "t3a.medium"]
  role_name_suffix             = "-apne2-az-c"
  tags                         = var.tags
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
# Compute — NLB (AZ-C only: ap-northeast-2c)
# ─────────────────────────────────────────────────────────────────────────────

module "nlb" {
  source = "../../../../modules/compute/nlb"

  environment       = var.environment
  region            = var.region
  vpc_id            = data.terraform_remote_state.shared.outputs.vpc_id
  public_subnet_ids = [data.terraform_remote_state.shared.outputs.public_subnet_ids[1]]
  security_group_id = data.terraform_remote_state.shared.outputs.nlb_security_group_id
  certificate_arn   = var.acm_certificate_arn
  name_override     = "prod-api-nlb-apne2-az-c"
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

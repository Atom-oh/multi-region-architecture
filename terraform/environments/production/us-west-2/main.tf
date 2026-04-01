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

# Remote state from primary region
data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = "multi-region-mall-terraform-state"
    key    = "production/us-east-1/terraform.tfstate"
    region = "us-east-1"
  }
}

# Global state not used - global resources (Aurora/DocDB global clusters)
# are referenced via variables instead
# data "terraform_remote_state" "global" {
#   backend = "s3"
#   config = {
#     bucket = "multi-region-mall-terraform-state"
#     key    = "global/terraform.tfstate"
#     region = "us-east-1"
#   }
# }

# ─────────────────────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../../modules/networking/vpc"

  environment          = var.environment
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  data_subnet_cidrs    = var.data_subnet_cidrs
  tags                 = var.tags
}

module "transit_gateway" {
  source = "../../../modules/networking/transit-gateway"

  environment             = var.environment
  vpc_ids                 = [module.vpc.vpc_id]
  attachment_subnet_ids   = [module.vpc.private_subnet_ids]
  create_peering          = true
  peer_region             = "us-east-1"
  peer_transit_gateway_id = data.terraform_remote_state.primary.outputs.transit_gateway_id
  peer_cidr_block         = "10.0.0.0/16"
  private_route_table_ids = module.vpc.private_route_table_ids
  data_route_table_ids    = module.vpc.data_route_table_ids
  tags                    = var.tags
}

module "security_groups" {
  source = "../../../modules/networking/security-groups"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = var.vpc_cidr
  tags        = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Security
# ─────────────────────────────────────────────────────────────────────────────

module "kms" {
  source = "../../../modules/security/kms"

  environment = var.environment
  region      = var.region
  tags        = var.tags
}

module "secrets_manager" {
  source = "../../../modules/security/secrets-manager"

  environment = var.environment
  region      = var.region
  kms_key_arn = module.kms.key_arns["aurora"]
  secrets = {
    documentdb = {
      name        = "${var.environment}/documentdb/credentials"
      description = "DocumentDB credentials"
    }
    msk = {
      name        = "${var.environment}/msk/credentials"
      description = "MSK SASL/SCRAM credentials"
    }
    opensearch = {
      name        = "${var.environment}/opensearch/credentials"
      description = "OpenSearch credentials"
    }
  }
  tags = var.tags
}

module "iam" {
  source = "../../../modules/security/iam"

  environment                = var.environment
  create_s3_replication_role = false # Already created in us-east-1 (global role)
  tags                       = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute
# ─────────────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../../modules/compute/eks"

  environment                   = var.environment
  region                        = var.region
  cluster_name                  = var.eks_cluster_name
  vpc_id                        = module.vpc.vpc_id
  private_subnet_ids            = module.vpc.private_subnet_ids
  alb_security_group_id         = module.security_groups.alb_security_group_id
  nlb_security_group_id         = module.security_groups.nlb_security_group_id
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
  source = "../../../modules/compute/alb"

  environment       = var.environment
  cluster_name      = var.eks_cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = module.vpc.vpc_id
  role_name_suffix  = "-us-west-2"
  tags              = var.tags
}

module "nlb" {
  source = "../../../modules/compute/nlb"

  environment       = var.environment
  region            = var.region
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.nlb_security_group_id
  certificate_arn   = var.acm_certificate_arn
  tags              = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Data (Secondary Region - Read Replicas)
# ─────────────────────────────────────────────────────────────────────────────

module "dsql" {
  source = "../../../modules/data/dsql"

  environment = var.environment
  region      = var.region
  tags        = var.tags
}

module "documentdb" {
  source = "../../../modules/data/documentdb-global"

  environment               = var.environment
  region                    = var.region
  is_primary                = false
  global_cluster_identifier = var.docdb_global_cluster_identifier
  source_region             = "us-east-1"
  vpc_id                    = module.vpc.vpc_id
  data_subnet_ids           = module.vpc.data_subnet_ids
  security_group_id         = module.security_groups.documentdb_security_group_id
  kms_key_arn               = module.kms.key_arns["documentdb"]
  instance_class            = "db.r6g.large"
  instance_count            = 1
  tags                      = var.tags
}

module "elasticache" {
  source = "../../../modules/data/elasticache-global"

  environment                 = var.environment
  region                      = var.region
  is_primary                  = false
  global_replication_group_id = data.terraform_remote_state.primary.outputs.elasticache_global_replication_group_id
  vpc_id                      = module.vpc.vpc_id
  data_subnet_ids             = module.vpc.data_subnet_ids
  security_group_id           = module.security_groups.elasticache_security_group_id
  kms_key_arn                 = module.kms.key_arns["elasticache"]
  node_type                   = "cache.r7g.medium"
  num_node_groups             = 2
  replicas_per_node_group     = 1
  tags                        = var.tags
}

module "msk" {
  source = "../../../modules/data/msk"

  environment            = var.environment
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  data_subnet_ids        = module.vpc.data_subnet_ids
  security_group_id      = module.security_groups.msk_security_group_id
  kms_key_arn            = module.kms.key_arns["msk"]
  broker_instance_type   = "kafka.t3.small"
  number_of_broker_nodes = 6   # t3 instances do not support broker removal
  ebs_volume_size        = 100 # MSK does not support EBS shrinkage
  enable_replicator      = false # Disabled: MSK clusters need IAM Auth enabled first
  source_cluster_arn     = data.terraform_remote_state.primary.outputs.msk_cluster_arn
  target_cluster_arn     = ""
  tags                   = var.tags
}

module "opensearch" {
  source = "../../../modules/data/opensearch"

  environment                = var.environment
  region                     = var.region
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  security_group_id          = module.security_groups.opensearch_security_group_id
  dedicated_master_enabled   = false
  data_instance_type         = "t3.small.search"
  data_instance_count        = 3
  ebs_volume_size            = 10
  enable_ultrawarm           = false
  create_service_linked_role = false # Already created in us-east-1
  tags                       = var.tags
}

module "s3" {
  source = "../../../modules/data/s3"

  environment                        = var.environment
  region                             = var.region
  is_primary                         = false
  static_assets_bucket_name          = "${var.environment}-mall-static-assets-${var.region}"
  analytics_bucket_name              = "${var.environment}-mall-analytics-${var.region}"
  replication_destination_bucket_arn = ""
  replication_role_arn               = ""
  kms_key_arn                        = module.kms.key_arns["s3"]
  tags                               = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Edge (Route53 latency record only - CloudFront/WAF managed from primary)
# ─────────────────────────────────────────────────────────────────────────────

module "route53" {
  source = "../../../modules/edge/route53"

  environment  = var.environment
  zone_id      = var.route53_zone_id
  lb_dns_names = { (var.region) = module.nlb.nlb_dns_name }
  lb_zone_ids  = { (var.region) = module.nlb.nlb_zone_id }
  tags         = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────────────────────

module "cloudwatch" {
  source = "../../../modules/observability/cloudwatch"

  environment      = var.environment
  region           = var.region
  eks_cluster_name = var.eks_cluster_name
  sns_topic_arn    = var.sns_topic_arn
  tags             = var.tags
}

module "xray" {
  source = "../../../modules/observability/xray"

  environment = var.environment
  tags        = var.tags
}

module "tempo_storage" {
  source = "../../../modules/observability/tempo-storage"

  environment       = var.environment
  region            = var.region
  kms_key_arn       = module.kms.key_arns["s3"]
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags
}

module "otel_collector_irsa" {
  source = "../../../modules/observability/otel-collector-irsa"

  environment       = var.environment
  region            = var.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags
}

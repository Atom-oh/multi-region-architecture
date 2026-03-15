terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82"
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
    aurora = {
      name        = "${var.environment}/aurora/credentials"
      description = "Aurora PostgreSQL credentials"
    }
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

  environment        = var.environment
  region             = var.region
  cluster_name       = var.eks_cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  tags               = var.tags
}

module "alb" {
  source = "../../../modules/compute/alb"

  environment       = var.environment
  cluster_name      = var.eks_cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = module.vpc.vpc_id
  tags              = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Data (Secondary Region - Read Replicas)
# ─────────────────────────────────────────────────────────────────────────────

module "aurora" {
  source = "../../../modules/data/aurora-global"

  environment               = var.environment
  region                    = var.region
  is_primary                = false
  global_cluster_identifier = var.aurora_global_cluster_identifier
  source_region             = "us-east-1"
  vpc_id                    = module.vpc.vpc_id
  data_subnet_ids           = module.vpc.data_subnet_ids
  security_group_id         = module.security_groups.aurora_security_group_id
  kms_key_arn               = module.kms.key_arns["aurora"]
  writer_instance_class     = "db.r6g.2xlarge"
  reader_instance_class     = "db.r6g.xlarge"
  reader_count              = 2
  tags                      = var.tags
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
  instance_class            = "db.r6g.2xlarge"
  instance_count            = 3
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
  node_type                   = "cache.r7g.xlarge"
  num_node_groups             = 3
  replicas_per_node_group     = 2
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
  broker_instance_type   = "kafka.m5.2xlarge"
  number_of_broker_nodes = 6
  ebs_volume_size        = 1000
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
  master_instance_type       = "r6g.large.search"
  master_instance_count      = 3
  data_instance_type         = "r6g.xlarge.search"
  data_instance_count        = 6
  ebs_volume_size            = 500
  enable_ultrawarm           = true
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

  environment   = var.environment
  zone_id       = var.route53_zone_id
  alb_dns_names = {} # ALB DNS not available until ALB controller deploys in EKS
  alb_zone_ids  = {}
  tags          = var.tags
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

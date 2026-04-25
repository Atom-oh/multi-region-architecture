terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
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
# Networking
# ─────────────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../../../modules/networking/vpc"

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
  source = "../../../../modules/networking/transit-gateway"

  environment             = var.environment
  vpc_ids                 = [module.vpc.vpc_id]
  attachment_subnet_ids   = [module.vpc.private_subnet_ids]
  create_peering          = false
  peer_cidr_block         = "10.1.0.0/16"
  private_route_table_ids = module.vpc.private_route_table_ids
  data_route_table_ids    = module.vpc.data_route_table_ids
  tags                    = var.tags
}

module "security_groups" {
  source = "../../../../modules/networking/security-groups"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = var.vpc_cidr
  tags        = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Security
# ─────────────────────────────────────────────────────────────────────────────

module "kms" {
  source = "../../../../modules/security/kms"

  environment = var.environment
  region      = var.region
  tags        = var.tags
}

module "secrets_manager" {
  source = "../../../../modules/security/secrets-manager"

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
  source = "../../../../modules/security/iam"

  environment                = var.environment
  region                     = "ap-northeast-2"
  create_github_actions_role = false
  github_org                 = "Atom-oh"
  terraform_state_bucket     = "multi-region-mall-terraform-state"
  terraform_lock_table       = "multi-region-mall-terraform-lock"
  bedrock_pr_review_model_id = "anthropic.claude-sonnet-4-6"
  bedrock_source_profile_arn = "arn:aws:bedrock:ap-northeast-2:013503698282:inference-profile/global.anthropic.claude-sonnet-4-6"
  tags                       = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute — NLB (needed before EKS for target group bindings)
# ─────────────────────────────────────────────────────────────────────────────

module "nlb" {
  source = "../../../../modules/compute/nlb"

  environment       = var.environment
  region            = var.region
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.nlb_security_group_id
  certificate_arn   = var.acm_certificate_arn
  tags              = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Data Stores
# ─────────────────────────────────────────────────────────────────────────────

resource "random_password" "aurora" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "random_password" "documentdb" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+"
}

module "aurora" {
  source = "../../../../modules/data/aurora-global"

  environment               = var.environment
  region                    = var.region
  is_primary                = true
  global_cluster_identifier = "multi-region-mall-aurora"
  vpc_id                    = module.vpc.vpc_id
  data_subnet_ids           = module.vpc.data_subnet_ids
  security_group_id         = module.security_groups.aurora_security_group_id
  kms_key_arn               = module.kms.key_arns["aurora"]
  master_password           = random_password.aurora.result
  writer_instance_class     = "db.r6g.2xlarge"
  reader_count              = 0
  tags                      = var.tags
}

module "dsql" {
  source = "../../../../modules/data/dsql"

  environment = var.environment
  region      = var.region
  tags        = var.tags
}

module "documentdb" {
  source = "../../../../modules/data/documentdb-global"

  environment                 = var.environment
  region                      = var.region
  is_primary                  = true
  global_cluster_identifier   = var.docdb_global_cluster_identifier
  cluster_identifier_override = "production-docdb-global-primary"
  vpc_id                      = module.vpc.vpc_id
  data_subnet_ids             = module.vpc.data_subnet_ids
  security_group_id           = module.security_groups.documentdb_security_group_id
  kms_key_arn                 = module.kms.key_arns["documentdb"]
  master_password             = random_password.documentdb.result
  instance_class              = "db.r6g.large"
  instance_count              = 1
  tags                        = var.tags
}

module "elasticache" {
  source = "../../../../modules/data/elasticache-global"

  environment                 = var.environment
  region                      = var.region
  is_primary                  = true
  global_replication_group_id = ""
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
  source = "../../../../modules/data/msk"

  environment            = var.environment
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  data_subnet_ids        = module.vpc.data_subnet_ids
  security_group_id      = module.security_groups.msk_security_group_id
  kms_key_arn            = module.kms.key_arns["msk"]
  broker_instance_type   = "kafka.t3.small"
  number_of_broker_nodes = 6
  ebs_volume_size        = 100
  enable_replicator      = false
  tags                   = var.tags
}

module "opensearch" {
  source = "../../../../modules/data/opensearch"

  environment              = var.environment
  region                   = var.region
  vpc_id                   = module.vpc.vpc_id
  data_subnet_ids          = module.vpc.data_subnet_ids
  security_group_id        = module.security_groups.opensearch_security_group_id
  dedicated_master_enabled = false
  data_instance_type       = "t3.small.search"
  data_instance_count      = 3
  ebs_volume_size          = 10
  enable_ultrawarm         = false
  tags                     = var.tags
}

module "s3" {
  source = "../../../../modules/data/s3"

  environment                        = var.environment
  region                             = var.region
  is_primary                         = true
  static_assets_bucket_name          = "${var.environment}-mall-static-assets-${var.region}"
  analytics_bucket_name              = "${var.environment}-mall-analytics-${var.region}"
  replication_destination_bucket_arn = null
  replication_role_arn               = ""
  kms_key_arn                        = module.kms.key_arns["s3"]
  tags                               = var.tags
}

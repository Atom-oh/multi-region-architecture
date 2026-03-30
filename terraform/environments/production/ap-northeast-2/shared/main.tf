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

# ─────────────────────────────────────────────────────────────────────────────
# Data (Korean Region)
# ─────────────────────────────────────────────────────────────────────────────

# Aurora: secondary, joining global cluster from primary
module "aurora" {
  source = "../../../../modules/data/aurora-global"

  environment               = var.environment
  region                    = var.region
  is_primary                = true
  global_cluster_identifier = ""
  source_region             = ""
  vpc_id                    = module.vpc.vpc_id
  data_subnet_ids           = module.vpc.data_subnet_ids
  security_group_id         = module.security_groups.documentdb_security_group_id
  kms_key_arn               = module.kms.key_arns["aurora"]
  master_password           = "<YOUR_PASSWORD>"
  reader_count              = 2
  reader_availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]
  tags                      = var.tags
}

# ElastiCache: standalone cluster (NOT joining global datastore — Korean region is independent)
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
  node_type                   = "cache.r6g.large"
  num_node_groups             = 1
  replicas_per_node_group     = 1
  tags                        = var.tags
}

# MSK: independent cluster for Korean region
# NOTE: server_properties (including replica.selector.class) is hardcoded in
# the MSK module — update the module if RackAwareReplicaSelector is needed.
module "msk" {
  source = "../../../../modules/data/msk"

  environment            = var.environment
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  data_subnet_ids        = module.vpc.data_subnet_ids
  security_group_id      = module.security_groups.msk_security_group_id
  kms_key_arn            = module.kms.key_arns["msk"]
  broker_instance_type   = "kafka.m5.large"
  number_of_broker_nodes = 4
  ebs_volume_size        = 100
  enable_replicator      = false
  tags                   = var.tags
}

# DocumentDB: secondary, joining global cluster from primary
module "documentdb" {
  source = "../../../../modules/data/documentdb-global"

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
  instance_count            = 2
  tags                      = var.tags
}

# OpenSearch: independent domain for Korean region
module "opensearch" {
  source = "../../../../modules/data/opensearch"

  environment                = var.environment
  region                     = var.region
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  security_group_id          = module.security_groups.opensearch_security_group_id
  master_instance_type       = "r6g.large.search"
  master_instance_count      = 3
  data_instance_type         = "r6g.large.search"
  data_instance_count        = 2
  availability_zone_count    = 2
  ebs_volume_size            = 100
  enable_ultrawarm           = false
  create_service_linked_role = false # Already created in us-east-1
  tags                       = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute — NLB (Multi-AZ, weighted routing to AZ-A + AZ-C target groups)
# ─────────────────────────────────────────────────────────────────────────────

module "nlb" {
  source = "../../../../modules/compute/nlb-weighted"

  environment       = var.environment
  region            = var.region
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.nlb_security_group_id
  certificate_arn   = var.acm_certificate_arn
  name_override     = "prod-api-nlb-apne2"

  target_groups = {
    az-a = { name = "prod-wtg-apne2-az-a", weight = 50 }
    az-c = { name = "prod-wtg-apne2-az-c", weight = 50 }
  }

  tags = var.tags
}

# S3: secondary (no replication source)
module "s3" {
  source = "../../../../modules/data/s3"

  environment                       = var.environment
  region                            = var.region
  is_primary                        = false
  static_assets_bucket_name         = "${var.environment}-mall-static-assets-${var.region}"
  analytics_bucket_name             = "${var.environment}-mall-analytics-${var.region}"
  replication_destination_bucket_arn = ""
  replication_role_arn              = ""
  kms_key_arn                       = module.kms.key_arns["s3"]
  tags                              = var.tags
}

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

# Read shared layer state for ElastiCache global replication group ID
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "multi-region-mall-terraform-state"
    key    = "production/us-east-1/shared/terraform.tfstate"
    region = "us-east-1"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DR Automation (Lambda-based failover for DocumentDB + ElastiCache)
# ─────────────────────────────────────────────────────────────────────────────

module "dr_automation" {
  source = "../../../../modules/dr-automation"

  environment                 = var.environment
  region                      = var.region
  docdb_global_cluster_id     = var.docdb_global_cluster_id
  docdb_target_cluster_id     = var.docdb_target_cluster_id
  elasticache_global_group_id = data.terraform_remote_state.shared.outputs.elasticache_global_replication_group_id
  elasticache_target_region   = var.elasticache_target_region
  elasticache_target_group_id = var.elasticache_target_group_id
  notification_email          = var.notification_email
  enable_auto_failover        = var.enable_auto_failover
  tags                        = var.tags
}

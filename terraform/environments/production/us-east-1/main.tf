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

# Remote state for global resources (optional - may not exist on initial deploy)
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
  create_peering          = false
  peer_cidr_block         = "10.1.0.0/16"
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

# Override S3 KMS key policy to allow CloudFront OAC decryption
resource "aws_kms_key_policy" "s3_cloudfront" {
  key_id = module.kms.key_ids["s3"]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::180294183052:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.distribution_arn
          }
        }
      }
    ]
  })
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

  environment = var.environment
  tags        = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute
# ─────────────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../../modules/compute/eks"

  environment           = var.environment
  region                = var.region
  cluster_name          = var.eks_cluster_name
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  nlb_security_group_id = module.security_groups.nlb_security_group_id
  bootstrap_node_instance_types = ["t3.medium", "t3a.medium"]
  role_name_suffix              = ""
  tags                          = var.tags

  addon_versions = {
    vpc_cni        = "v1.21.1-eksbuild.3"
    coredns        = "v1.13.2-eksbuild.3"
    kube_proxy     = "v1.35.0-eksbuild.2"
    ebs_csi_driver = "v1.56.0-eksbuild.1"
    efs_csi_driver = "v2.3.0-eksbuild.2"
  }
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
# Data
# ─────────────────────────────────────────────────────────────────────────────

resource "random_password" "documentdb" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+"
}

module "dsql" {
  source = "../../../modules/data/dsql"

  environment = var.environment
  region      = var.region
  tags        = var.tags
}

module "dsql_irsa" {
  source = "../../../modules/data/dsql-irsa"

  environment       = var.environment
  region            = var.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  dsql_cluster_arn  = module.dsql.cluster_arn
  tags              = var.tags
}

module "documentdb" {
  source = "../../../modules/data/documentdb-global"

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
  instance_count              = 2
  tags                        = var.tags
}

module "elasticache" {
  source = "../../../modules/data/elasticache-global"

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
  source = "../../../modules/data/msk"

  environment            = var.environment
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  data_subnet_ids        = module.vpc.data_subnet_ids
  security_group_id      = module.security_groups.msk_security_group_id
  kms_key_arn            = module.kms.key_arns["msk"]
  broker_instance_type   = "kafka.m5.large"
  number_of_broker_nodes = 3
  ebs_volume_size        = 100
  enable_replicator      = false # Replicator configured separately after both clusters exist
  tags                   = var.tags
}

module "opensearch" {
  source = "../../../modules/data/opensearch"

  environment           = var.environment
  region                = var.region
  vpc_id                = module.vpc.vpc_id
  data_subnet_ids       = module.vpc.data_subnet_ids
  security_group_id     = module.security_groups.opensearch_security_group_id
  master_instance_type  = "r6g.medium.search"
  master_instance_count = 3
  data_instance_type    = "r6g.medium.search"
  data_instance_count   = 3
  ebs_volume_size       = 100
  enable_ultrawarm      = false
  tags                  = var.tags
}

module "s3" {
  source = "../../../modules/data/s3"

  environment                        = var.environment
  region                             = var.region
  is_primary                         = true
  static_assets_bucket_name          = "${var.environment}-mall-static-assets-${var.region}"
  analytics_bucket_name              = "${var.environment}-mall-analytics-${var.region}"
  replication_destination_bucket_arn = null # Set after west bucket exists
  replication_role_arn               = ""
  kms_key_arn                        = module.kms.key_arns["s3"]
  tags                               = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Edge
# ─────────────────────────────────────────────────────────────────────────────

module "waf" {
  source = "../../../modules/edge/waf"

  environment = var.environment
  tags        = var.tags
}

module "route53" {
  source = "../../../modules/edge/route53"

  environment  = var.environment
  zone_id      = var.route53_zone_id
  lb_dns_names = { (var.region) = module.nlb.nlb_dns_name }
  lb_zone_ids  = { (var.region) = module.nlb.nlb_zone_id }
  tags         = var.tags
}

module "cloudfront" {
  source = "../../../modules/edge/cloudfront"

  environment                      = var.environment
  domain_name                      = var.domain_name
  acm_certificate_arn              = var.acm_certificate_arn
  static_assets_bucket_domain_name = module.s3.static_assets_bucket_domain_name
  static_assets_bucket_id          = module.s3.static_assets_bucket_id
  api_domain_name                  = "api-internal.${var.domain_name}"
  waf_web_acl_id                   = "" # temporarily disabled — WAF Bot Control blocks curl/headless browsers
  tags                             = var.tags
}

module "cloudfront_argocd" {
  source = "../../../modules/edge/cloudfront-argocd"

  environment     = var.environment
  domain_name     = var.domain_name
  acm_certificate_arn = var.acm_certificate_arn
  waf_web_acl_arn = "" # WAF disabled — bot control rules block ArgoCD API/gRPC; ArgoCD has its own auth
  tags            = var.tags
}

# ArgoCD Route53 records
resource "aws_route53_record" "argocd" {
  zone_id = var.route53_zone_id
  name    = "argocd.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.cloudfront_argocd.distribution_domain_name
    zone_id                = module.cloudfront_argocd.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

module "cloudfront_grafana" {
  source = "../../../modules/edge/cloudfront-grafana"

  environment     = var.environment
  domain_name     = var.domain_name
  acm_certificate_arn = var.acm_certificate_arn
  waf_web_acl_arn = "" # WAF disabled — Grafana has its own auth
  tags            = var.tags
}

# Grafana Route53 records (primary region only)
resource "aws_route53_record" "grafana" {
  zone_id = var.route53_zone_id
  name    = "grafana.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.cloudfront_grafana.distribution_domain_name
    zone_id                = module.cloudfront_grafana.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "grafana_internal" {
  count = var.grafana_nlb_dns_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "grafana-internal.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.grafana_nlb_dns_name
    zone_id                = var.grafana_nlb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "argocd_internal" {
  count = var.argocd_nlb_dns_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "argocd-internal.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.argocd_nlb_dns_name
    zone_id                = var.argocd_nlb_zone_id
    evaluate_target_health = true
  }

  set_identifier = var.region

  latency_routing_policy {
    region = var.region
  }
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

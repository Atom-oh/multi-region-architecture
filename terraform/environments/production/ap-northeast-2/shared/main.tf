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

  environment                = var.environment
  region                     = var.region
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  security_group_id          = module.security_groups.msk_security_group_id
  kms_key_arn                = module.kms.key_arns["msk"]
  broker_instance_type   = "kafka.t3.small"
  number_of_broker_nodes = 4   # t3 instances do not support broker removal
  ebs_volume_size        = 100 # MSK does not support EBS shrinkage
  kafka_version              = "3.9.x"
  enable_replicator          = false
  tags                       = var.tags
}

# DocumentDB: independent primary cluster for Korean region
# Data seeded via one-time copy from US (mongodump/mongorestore)
module "documentdb" {
  source = "../../../../modules/data/documentdb-global"

  environment               = var.environment
  region                    = var.region
  is_primary                = true
  global_cluster_identifier = ""
  source_region             = ""
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
  dedicated_master_enabled   = false
  data_instance_type         = "t3.small.search"
  data_instance_count        = 2
  availability_zone_count    = 2
  ebs_volume_size            = 10
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

# ─────────────────────────────────────────────────────────────────────────────
# Route53 — Korea-specific DNS records
# ─────────────────────────────────────────────────────────────────────────────

# mall-kr.atomai.click → Korea mall NLB
resource "aws_route53_record" "mall_kr" {
  zone_id = var.route53_zone_id
  name    = "mall-kr.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.nlb.nlb_dns_name
    zone_id                = module.nlb.nlb_zone_id
    evaluate_target_health = true
  }
}

# api-kr.atomai.click → Korea API NLB (same NLB, separate DNS for API calls)
resource "aws_route53_record" "api_kr" {
  zone_id = var.route53_zone_id
  name    = "api-kr.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.nlb.nlb_dns_name
    zone_id                = module.nlb.nlb_zone_id
    evaluate_target_health = true
  }
}

# argocd-kr.atomai.click → ArgoCD NLB (created by K8s LB controller on mgmt cluster)
resource "aws_route53_record" "argocd_kr" {
  count = var.argocd_nlb_dns_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "argocd-kr.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.argocd_nlb_dns_name
    zone_id                = var.argocd_nlb_zone_id
    evaluate_target_health = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudFront — Mall (mall.atomai.click → CF → S3 + Korea NLB)
#
# us-east-1's CloudFront/EKS/data-plane infra has been decommissioned; this
# replaces it as mall.<domain>'s origin. api_domain_name relies on the
# existing api-internal.<domain> alias (already points at the Korea NLB).
# The module also declares www.<domain> as an alias, but that hostname still
# points at us-east-1's (defunct) distribution — out of scope here.
# ─────────────────────────────────────────────────────────────────────────────

module "cloudfront" {
  source = "../../../../modules/edge/cloudfront"

  environment                      = var.environment
  domain_name                      = var.domain_name
  acm_certificate_arn              = var.cloudfront_acm_certificate_arn
  static_assets_bucket_domain_name = module.s3.static_assets_bucket_domain_name
  static_assets_bucket_id          = module.s3.static_assets_bucket_id
  api_domain_name                  = "api-internal.${var.domain_name}"
  waf_web_acl_id                   = ""
  tags                             = var.tags
}

data "aws_caller_identity" "current" {}

# The cloudfront module only creates the OAC — nothing grants it access to
# the bucket or its SSE-KMS key. us-east-1 has the same gap (its module call
# has no matching bucket policy either); adding both here since without them
# every S3-origin request through this distribution 403s.
resource "aws_s3_bucket_policy" "static_assets_cloudfront" {
  bucket = module.s3.static_assets_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${module.s3.static_assets_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.distribution_arn
          }
        }
      }
    ]
  })
}

resource "aws_kms_key_policy" "s3_cloudfront" {
  key_id = module.kms.key_ids["s3"]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.distribution_arn
          }
        }
      }
    ]
  })
}

resource "aws_route53_record" "mall" {
  zone_id = var.route53_zone_id
  name    = "mall.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.cloudfront.distribution_domain_name
    zone_id                = module.cloudfront.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudFront — ArgoCD Korea (argocd-korea.atomai.click → CF → NLB → ArgoCD)
# ─────────────────────────────────────────────────────────────────────────────

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "argocd_korea" {
  count = var.argocd_nlb_dns_name != "" && var.cloudfront_acm_certificate_arn != "" ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "ArgoCD Korea (argocd-korea.${var.domain_name})"
  price_class     = "PriceClass_200"
  http_version    = "http2and3"
  aliases         = ["argocd-korea.${var.domain_name}"]

  origin {
    domain_name = var.argocd_nlb_dns_name
    origin_id   = "argocd-nlb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "argocd-nlb"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]
  }

  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, {
    Name    = "argocd-korea-cloudfront"
    Service = "argocd"
  })
}

# argocd-korea.atomai.click → CloudFront
resource "aws_route53_record" "argocd_korea" {
  count = var.argocd_nlb_dns_name != "" && var.cloudfront_acm_certificate_arn != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "argocd-korea.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.argocd_korea[0].domain_name
    zone_id                = aws_cloudfront_distribution.argocd_korea[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# CloudFront — Grafana Korea (grafana-kr.atomai.click → CF → NLB → Grafana)
resource "aws_cloudfront_distribution" "grafana_korea" {
  count = var.grafana_nlb_dns_name != "" && var.cloudfront_acm_certificate_arn != "" ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "Grafana Korea (grafana-kr.${var.domain_name})"
  price_class     = "PriceClass_200"
  http_version    = "http2and3"
  aliases         = ["grafana-kr.${var.domain_name}"]

  origin {
    domain_name = var.grafana_nlb_dns_name
    origin_id   = "grafana-nlb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "grafana-nlb"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]
  }

  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, {
    Name    = "grafana-korea-cloudfront"
    Service = "grafana"
  })
}

# grafana-kr.atomai.click → CloudFront
resource "aws_route53_record" "grafana_kr" {
  count = var.grafana_nlb_dns_name != "" && var.cloudfront_acm_certificate_arn != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "grafana-kr.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.grafana_korea[0].domain_name
    zone_id                = aws_cloudfront_distribution.grafana_korea[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — GitHub Actions OIDC role (runners on ap-northeast-2 mgmt cluster)
# ─────────────────────────────────────────────────────────────────────────────

module "iam" {
  source = "../../../../modules/security/iam"

  environment                = var.environment
  region                     = var.region
  create_github_actions_role = true
  github_org                 = "Atom-oh"
  terraform_state_bucket     = "multi-region-mall-terraform-state"
  terraform_lock_table       = "multi-region-mall-terraform-lock"
  bedrock_pr_review_model_id = "anthropic.claude-sonnet-4-6"
  bedrock_source_profile_arn = "arn:aws:bedrock:ap-northeast-2:013503698282:inference-profile/global.anthropic.claude-sonnet-4-6"
  tags                       = var.tags
}

# S3: secondary (no replication source)
module "s3" {
  source = "../../../../modules/data/s3"

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
# IAM — External Secrets Operator IRSA (az-a + az-c)
#
# k8s/infra/external-secrets/ (ClusterSecretStore + ExternalSecret CRs) was
# never wired into any ArgoCD Application for Korea — only the operator's
# Helm chart was, via appset-helm-external-secrets.yaml. Without this role,
# and without the CRs applied, no data-store secrets ever reach the cluster.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_eks_cluster" "az_a" {
  name = "mall-apne2-az-a"
}

data "aws_eks_cluster" "az_c" {
  name = "mall-apne2-az-c"
}

resource "aws_iam_role" "external_secrets" {
  name = "mall-apne2-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for cluster in [data.aws_eks_cluster.az_a, data.aws_eks_cluster.az_c] : {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(cluster.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets-sa"
            "${replace(cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "external_secrets_read" {
  name = "secrets-manager-read"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:mall/*"
      }
    ]
  })
}

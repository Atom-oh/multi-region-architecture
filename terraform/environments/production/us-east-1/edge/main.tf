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
    key    = "production/us-east-1/shared/terraform.tfstate"
    region = "us-east-1"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# WAF
# ─────────────────────────────────────────────────────────────────────────────

module "waf" {
  source = "../../../../modules/edge/waf"

  environment = var.environment
  tags        = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudFront
# ─────────────────────────────────────────────────────────────────────────────

module "cloudfront" {
  source = "../../../../modules/edge/cloudfront"

  environment                      = var.environment
  domain_name                      = var.domain_name
  acm_certificate_arn              = var.acm_certificate_arn
  static_assets_bucket_domain_name = data.terraform_remote_state.shared.outputs.s3_static_assets_bucket_domain_name
  static_assets_bucket_id          = data.terraform_remote_state.shared.outputs.s3_static_assets_bucket_id
  api_domain_name                  = "api-internal.${var.domain_name}"
  waf_web_acl_id                   = ""
  tags                             = var.tags
}

# Override S3 KMS key policy to allow CloudFront OAC decryption
resource "aws_kms_key_policy" "s3_cloudfront" {
  key_id = data.terraform_remote_state.shared.outputs.kms_key_ids["s3"]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::123456789012:root"
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

module "cloudfront_argocd" {
  source = "../../../../modules/edge/cloudfront-argocd"

  environment         = var.environment
  domain_name         = var.domain_name
  acm_certificate_arn = var.acm_certificate_arn
  waf_web_acl_arn     = ""
  tags                = var.tags
}

module "cloudfront_grafana" {
  source = "../../../../modules/edge/cloudfront-grafana"

  environment         = var.environment
  domain_name         = var.domain_name
  acm_certificate_arn = var.acm_certificate_arn
  waf_web_acl_arn     = ""
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Route53
# ─────────────────────────────────────────────────────────────────────────────

module "route53" {
  source = "../../../../modules/edge/route53"

  environment  = var.environment
  zone_id      = var.route53_zone_id
  lb_dns_names = { (var.region) = data.terraform_remote_state.shared.outputs.nlb_dns_name }
  lb_zone_ids  = { (var.region) = data.terraform_remote_state.shared.outputs.nlb_zone_id }
  tags         = var.tags
}

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
# Authentication
# ─────────────────────────────────────────────────────────────────────────────

module "cognito" {
  source      = "../../../../modules/security/cognito"
  environment = var.environment
  region      = var.region
  tags        = var.tags
}

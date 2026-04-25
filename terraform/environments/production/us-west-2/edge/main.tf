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
# Route53 (latency-based record only — CloudFront/WAF managed from us-east-1)
# ─────────────────────────────────────────────────────────────────────────────

module "route53" {
  source = "../../../../modules/edge/route53"

  environment  = var.environment
  zone_id      = var.route53_zone_id
  lb_dns_names = { (var.region) = data.terraform_remote_state.shared.outputs.nlb_dns_name }
  lb_zone_ids  = { (var.region) = data.terraform_remote_state.shared.outputs.nlb_zone_id }
  tags         = var.tags
}

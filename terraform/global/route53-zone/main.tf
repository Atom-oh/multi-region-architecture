terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name        = var.domain_name
    Purpose     = "Primary DNS Zone"
    Environment = "global"
  }
}

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_dsql_cluster" "this" {
  deletion_protection_enabled = var.deletion_protection_enabled

  tags = merge(var.tags, {
    Name        = "${var.environment}-dsql-${var.region}"
    Environment = var.environment
  })
}

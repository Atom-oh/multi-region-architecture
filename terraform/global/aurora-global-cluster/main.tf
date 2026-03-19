terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_rds_global_cluster" "main" {
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = "aurora-postgresql"
  engine_version            = "17.7"
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
}

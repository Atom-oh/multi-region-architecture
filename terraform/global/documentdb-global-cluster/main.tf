terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82"
    }
  }
}

resource "aws_docdb_global_cluster" "main" {
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = "docdb"
  engine_version            = "5.0.0"
  storage_encrypted         = true
  deletion_protection       = true
}

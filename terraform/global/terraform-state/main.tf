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
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = var.state_bucket_name
    Purpose     = "Terraform State Storage"
    Environment = "global"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────────────────────────────────────
# State custody — keep this repo's CI out of state objects another repo owns.
#
# The identity policy on github-actions-role already denies the mgmt state key
# (modules/security/iam/github-actions.tf, DenyAccessToExternallyOwnedState), but
# an identity Deny only binds the one principal it is attached to. The mgmt
# cluster's own CI role (mall-apne2-mgmt-ci-runner, owned by AWS-Demo-Platform)
# carries AmazonS3FullAccess and ReadOnlyAccess and is pod-identity-bound to
# every self-hosted runner SA — so runner pods could read and write the whole
# bucket, including the shared/ state that holds Aurora and DocumentDB master
# passwords in plaintext.
#
# A bucket policy is what actually closes that: an explicit Deny here wins over
# any Allow in any identity policy, so attaching a managed FullAccess policy no
# longer grants it. That is the difference between this and a README warning —
# the reason it belongs in the same change as the ownership handoff.
#
# Scoped to non-owner principals, not to everyone: whoever applies
# AWS-Demo-Platform/infra/eks-mgmt still has to write its own state object, and
# whoever applies this repo's layers still has to write theirs.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket_policy" "terraform_state" {
  count  = length(var.state_custody_denials) == 0 ? 0 : 1
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        # Unconditional: nothing has a reason to reach state over plaintext HTTP,
        # and a state object in flight is the densest secret this account moves.
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource = [
            aws_s3_bucket.terraform_state.arn,
            "${aws_s3_bucket.terraform_state.arn}/*",
          ]
          Condition = {
            Bool = { "aws:SecureTransport" = "false" }
          }
        }
      ],
      [
        for name, keys in var.state_custody_denials : {
          # NotPrincipal is deliberately not used: it is famously easy to get
          # wrong (a role's assumed-role session ARN differs from the role ARN,
          # so an exception list silently fails open). Naming the denied
          # principals directly means a mistake here fails closed — that role
          # loses access — rather than granting the world.
          Sid       = "Deny${replace(title(replace(name, "-", " ")), " ", "")}StateAccess"
          Effect    = "Deny"
          Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}" }
          Action    = "s3:*"
          Resource  = [for key in keys : "${aws_s3_bucket.terraform_state.arn}/${key}"]
        }
      ]
    )
  })
}

data "aws_caller_identity" "current" {}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = var.lock_table_name
    Purpose     = "Terraform State Locking"
    Environment = "global"
  }
}

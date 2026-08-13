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
        # NotPrincipal is deliberately not used: it is famously easy to get
        # wrong (a role's assumed-role session ARN differs from the role ARN,
        # so an exception list silently fails open). Naming the denied
        # principals directly means a mistake here fails closed — that role
        # loses access — rather than granting the world.
        #
        # Principal is "*" with an aws:PrincipalArn condition, not
        # `Principal = { AWS = "arn:...:role/name" }` (round-8 review CRITICAL,
        # confirmed against diff). A role-ARN Principal is stored by AWS as
        # that role's *unique internal principal ID* at policy-save time — if
        # the external repo that owns mall-apne2-mgmt-ci-runner ever recreates
        # the role (routine maintenance there, not an attack), the new role
        # gets a new principal ID this Deny no longer matches, and custody
        # silently reopens with no signal here. aws:PrincipalArn is evaluated
        # against the assumed-role session's role ARN at request time — same
        # ARN before and after a role recreation — so it stays fail-closed
        # across exactly the event this policy exists to survive. It also
        # avoids a cold-bootstrap failure: a role-ARN Principal makes
        # PutBucketPolicy itself fail with "Invalid principal" if the role
        # doesn't exist yet.
        for name, keys in var.state_custody_denials : {
          Sid       = "Deny${replace(title(replace(name, "-", " ")), " ", "")}StateAccess"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          # Both the exact key and its env:/ workspace variant — same gap as the
          # identity-policy Deny (github-actions.tf): a workspace object lives
          # under the bucket-root env:/ prefix, not under the key's own prefix,
          # so an exact-key-only list leaves it open to a second writer.
          Resource = flatten([
            for key in keys : [
              "${aws_s3_bucket.terraform_state.arn}/${key}",
              "${aws_s3_bucket.terraform_state.arn}/env:/*/${key}",
            ]
          ])
          Condition = {
            StringLike = {
              "aws:PrincipalArn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"
            }
          }
        }
      ],
      [
        # The object-key Deny above is itself removable by a denied principal:
        # AmazonS3FullAccess grants s3:PutBucketPolicy/DeleteBucketPolicy on the
        # bucket ARN, which the object-key Resource above doesn't cover (object
        # Denies don't protect the bucket's own policy document). A principal
        # blocked from reading shared/'s state could otherwise call
        # PutBucketPolicy to drop this Deny, then read it. This Deny is scoped
        # to the bucket ARN and policy/configuration-mutation actions only —
        # it does not touch the object-level read/write this policy already
        # governs above, so appliers of this repo's own layers are unaffected.
        # Same Principal="*" + aws:PrincipalArn reasoning as above.
        for name, keys in var.state_custody_denials : {
          Sid       = "Deny${replace(title(replace(name, "-", " ")), " ", "")}BucketPolicyMutation"
          Effect    = "Deny"
          Principal = "*"
          Action = [
            "s3:PutBucketPolicy",
            "s3:DeleteBucketPolicy",
            "s3:PutBucketAcl",
            "s3:PutBucketPublicAccessBlock",
            "s3:PutLifecycleConfiguration",
            "s3:PutBucketVersioning",
            "s3:PutReplicationConfiguration",
          ]
          Resource = aws_s3_bucket.terraform_state.arn
          Condition = {
            StringLike = {
              "aws:PrincipalArn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"
            }
          }
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

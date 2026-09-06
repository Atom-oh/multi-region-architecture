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
# State custody — only the appliers of a layer may touch its state: this repo's
# applier group on this repo's keys, the other repo's appliers on the one key
# it owns, and nobody else.
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
# Scoped as an ALLOWLIST, not a denylist (round-15; round-13/14 review
# CRITICAL-2, 3/3 models, confirmed): rounds 8–14 denied the runner role by
# naming its ARN in an aws:PrincipalArn condition. That only matches calls made
# *as that role*. The role also holds `sts:AssumeRole role/cdk-*` and
# `iam:PassRole role/* (ecs-tasks)` + `ecs:RunTask` (owned by the other repo),
# i.e. at least two ways to become a different principal ARN — and a Deny keyed
# on the listed ARN never matches those sessions. Whoever applies
# AWS-Demo-Platform/infra/eks-mgmt and whoever applies this repo's layers still
# has to write their own state object, so the statement now denies everyone
# who is NOT one of those appliers. A pivot session is denied by construction.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  account_id = data.aws_caller_identity.current.account_id
  # Role names -> ARNs, account prefixed at plan time (no account ID in git).
  state_custody_applier_arns = [
    for r in var.state_custody_appliers : "arn:aws:iam::${local.account_id}:role/${r}"
  ]
  external_state_applier_arns = {
    for key, roles in var.external_state_appliers :
    key => [for r in roles : "arn:aws:iam::${local.account_id}:role/${r}"]
  }
  # Keys governed by this repo's applier group alone = protected minus external.
  internal_state_keys = [
    for key in var.protected_state_keys : key if !contains(keys(var.external_state_appliers), key)
  ]
  # Every key plus its env:/ workspace variant — same gap as the identity-policy
  # Deny (github-actions.tf): a workspace object lives under the bucket-root
  # env:/ prefix, not under the key's own prefix, so an exact-key-only list
  # leaves it open to a second writer.
  internal_state_resources = flatten([
    for key in local.internal_state_keys : [
      "${aws_s3_bucket.terraform_state.arn}/${key}",
      "${aws_s3_bucket.terraform_state.arn}/env:/*/${key}",
    ]
  ])

  # ── Self-lockout guard (round-16 review L2 MAJOR, confirmed) ──────────────
  # Whoever runs `terraform apply` here must be on the allowlist: PutBucketPolicy
  # would succeed and the very next call — writing this layer's own state under
  # global/* — would be denied, leaving state and reality split and the caller
  # without the permission to fix the policy (root only). aws:PrincipalArn is
  # compared as the ROLE ARN with path, but the caller identity of an assumed
  # role is `arn:aws:sts::<acct>:assumed-role/<RoleName>/<session>` — the path
  # is dropped and the name is what remains — so the check normalises both
  # sides to the role NAME and applies the applier patterns' `*` as a glob.
  # Root (`arn:aws:iam::<acct>:root`) can always rewrite its own bucket policy
  # and is accepted. IAM users are not appliers here and fail the check.
  caller_resource = element(split(":", data.aws_caller_identity.current.arn), 5)
  caller_role_name = (
    startswith(local.caller_resource, "assumed-role/") ? split("/", local.caller_resource)[1] :
    startswith(local.caller_resource, "role/") ? element(split("/", local.caller_resource), length(split("/", local.caller_resource)) - 1) :
    null
  )
  applier_name_regexes = [
    for r in var.state_custody_appliers :
    "^${replace(replace(element(split("/", r), length(split("/", r)) - 1), ".", "\\."), "*", ".*")}$"
  ]
  caller_is_applier = local.caller_resource == "root" || (
    local.caller_role_name != null && anytrue([for re in local.applier_name_regexes : can(regex(re, local.caller_role_name))])
  )
}

resource "aws_s3_bucket_policy" "terraform_state" {
  count  = length(var.protected_state_keys) == 0 ? 0 : 1
  bucket = aws_s3_bucket.terraform_state.id

  lifecycle {
    # An allowlist with nobody on it is a deny-everyone policy on every layer's
    # state. Refuse to plan it rather than create it: this is the one shape of
    # mistake that a later apply cannot fix from inside Terraform (root's
    # PutBucketPolicy would be the only way back).
    precondition {
      condition     = length(var.state_custody_appliers) > 0
      error_message = "state_custody_appliers is empty: this would deny every principal access to protected_state_keys (self-lockout). Set protected_state_keys = [] to disable the policy instead."
    }
    # The principal applying this policy must be an applier, or it locks itself
    # out of this layer's own state on the next call (see locals).
    precondition {
      condition     = local.caller_is_applier
      error_message = "The current caller (${data.aws_caller_identity.current.arn}) matches none of state_custody_appliers. Applying this bucket policy would deny your own next state write under global/* and remove your permission to fix it (recovery: account root PutBucketPolicy). Add the caller's role to state_custody_appliers, or apply from a listed applier."
    }
    precondition {
      condition     = alltrue([for k in keys(var.external_state_appliers) : contains(var.protected_state_keys, k)])
      error_message = "Every key in external_state_appliers must also be listed in protected_state_keys — otherwise that key is not protected at all and the per-key allowlist is dead configuration."
    }
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
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
      },
      # Object custody: deny s3:* on protected keys to every principal whose
      # aws:PrincipalArn matches none of the applier patterns. Object-level only
      # by design: s3:ListBucket / ListBucketVersions on the bucket ARN stay
      # open to non-appliers, so key names and version metadata are visible —
      # contents are not (round-16 review L3 MINOR, accepted: other layers'
      # appliers need to list their own prefixes and the leak is metadata).
      #
      # NotPrincipal is deliberately not used: it is famously easy to get wrong
      # (a role's assumed-role session ARN differs from the role ARN, so an
      # exception list silently fails open). Principal="*" + a StringNotLike
      # aws:PrincipalArn condition is the documented allowlist shape — and
      # aws:PrincipalArn is evaluated against the assumed-role session's ROLE
      # ARN at request time, so it survives role recreation (round-8 review
      # CRITICAL: a role-ARN Principal pins to the role's internal principal ID
      # at policy-save time and silently fails open once the role is recreated;
      # it also makes PutBucketPolicy itself fail with "Invalid principal" if
      # the role doesn't exist yet).
      #
      # Failure modes to keep in mind (the mirror image of the denylist's):
      #   - a mistyped or missing applier pattern LOCKS THAT APPLIER OUT (loud,
      #     fail-closed: its next plan/apply errors on state access) rather than
      #     silently letting the target through — the direction we want;
      #   - the account root is not on the list and is denied object access
      #     too, but root can always PutBucketPolicy on its own bucket, so a
      #     manual recovery path exists;
      #   - the human SSO admin entry is wildcarded on its permission-set hash so
      #     routine Identity Center re-provisioning cannot lock the humans out.
      {
        Sid       = "DenyProtectedStateAccessExceptAppliers"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = local.internal_state_resources
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = local.state_custody_applier_arns
          }
        }
      }],
      # Externally-owned keys: this repo's appliers ∪ that repo's appliers, and
      # nobody else — the other repo's roles are exempt HERE and only here, so
      # they never reach shared/, the spokes, US or global/ state.
      [for i, key in sort(keys(var.external_state_appliers)) : {
        Sid       = "DenyExternalStateAccessExceptAppliers${i}"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "${aws_s3_bucket.terraform_state.arn}/${key}",
          "${aws_s3_bucket.terraform_state.arn}/env:/*/${key}",
        ]
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = concat(local.state_custody_applier_arns, local.external_state_applier_arns[key])
          }
        }
      }],
      [
        # The object Deny above is itself removable by a non-applier that holds
        # s3:PutBucketPolicy/DeleteBucketPolicy on the bucket ARN (AmazonS3FullAccess
        # does): object Denies don't protect the bucket's own policy document. So
        # the same allowlist also guards policy/configuration mutation on the
        # bucket ARN. Object-level read/write is governed above, not here, so a
        # listed applier of a single layer is unaffected by this statement.
        {
          Sid       = "DenyBucketPolicyMutationExceptAppliers"
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
            "s3:PutEncryptionConfiguration",
            "s3:PutBucketNotification",
            "s3:DeleteBucket",
          ]
          Resource = aws_s3_bucket.terraform_state.arn
          Condition = {
            StringNotLike = {
              "aws:PrincipalArn" = local.state_custody_applier_arns
            }
          }
        },
    ])
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

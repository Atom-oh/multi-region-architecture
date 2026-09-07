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
  external_state_reader_arns = {
    for key, roles in var.external_state_readers :
    key => [for r in roles : "arn:aws:iam::${local.account_id}:role/${r}"]
  }
  state_custody_reader_arns = [
    for r in var.state_custody_readers : "arn:aws:iam::${local.account_id}:role/${r}"
  ]
  state_read_actions = ["s3:GetObject", "s3:GetObjectVersion"]
  # Keys governed by this repo's applier group alone = protected minus the
  # externally-applied and the externally-read ones (each gets its own Sid).
  internal_state_keys = [
    for key in var.protected_state_keys : key
    if !contains(keys(var.external_state_appliers), key) && !contains(keys(var.external_state_readers), key)
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

  # ── Self-lockout guard (round-16 review L2 MAJOR; tightened round-17) ─────
  # Whoever runs `terraform apply` here must be on the allowlist: PutBucketPolicy
  # would succeed and the very next call — writing this layer's own state under
  # global/* — would be denied, leaving state and reality split and the caller
  # without the permission to fix the policy. The caller identity of an assumed
  # role is `arn:aws:sts::<acct>:assumed-role/<RoleName>/<session>` — no path —
  # while aws:PrincipalArn is evaluated against the role ARN WITH path, so the
  # round-16 name-only glob let a path typo in the applier list (the SSO
  # `aws-reserved/...` entry is the obvious one) pass the plan and lock that
  # applier out at runtime (round-17 review L3 MAJOR). Now the role name is
  # resolved back to its full ARN with `iam:GetRole` and compared against the
  # same ARN patterns the policy uses, `*` as a glob. Root is REJECTED, not
  # accepted (round-17 L4 MAJOR): the object Deny has no root exemption, so
  # applying as root would split policy and state exactly as described above.
  # Root's ability to PutBucketPolicy remains the manual recovery path only.
  caller_resource = element(split(":", data.aws_caller_identity.current.arn), 5)
  caller_role_name = (
    startswith(local.caller_resource, "assumed-role/") ? split("/", local.caller_resource)[1] :
    startswith(local.caller_resource, "role/") ? element(split("/", local.caller_resource), length(split("/", local.caller_resource)) - 1) :
    null
  )
  caller_role_arn = local.caller_role_name == null ? null : one(data.aws_iam_role.caller[*].arn)
  applier_arn_regexes = [
    for a in local.state_custody_applier_arns : "^${replace(replace(a, ".", "\\."), "*", ".*")}$"
  ]
  caller_is_applier = local.caller_role_arn != null && anytrue([
    for re in local.applier_arn_regexes : can(regex(re, local.caller_role_arn))
  ])
}

# Resolves the calling role's full ARN (with path) — see caller_is_applier.
data "aws_iam_role" "caller" {
  count = local.caller_role_name == null ? 0 : 1
  name  = local.caller_role_name
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
      error_message = "The current caller (${data.aws_caller_identity.current.arn}, role ARN ${coalesce(local.caller_role_arn, "n/a — not a role; root and IAM users may not apply this layer")}) matches none of state_custody_appliers (compared as full role ARNs with path). Applying this bucket policy would deny your own next state write under global/* and remove your permission to fix it (recovery: account root PutBucketPolicy). Add the caller's role to state_custody_appliers, or apply from a listed applier."
    }
    precondition {
      condition     = alltrue([for k in concat(keys(var.external_state_appliers), keys(var.external_state_readers)) : contains(var.protected_state_keys, k)])
      error_message = "Every key in external_state_appliers / external_state_readers must also be listed in protected_state_keys — otherwise that key is not protected at all and the per-key allowlist is dead configuration."
    }
    precondition {
      condition     = length(setintersection(toset(keys(var.external_state_appliers)), toset(keys(var.external_state_readers)))) == 0
      error_message = "A key cannot be in both external_state_appliers and external_state_readers — decide whether the other repo applies it or only reads it."
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
      # This repo's own keys, two statements (round-18 L2/L3 MAJOR — the CI plan
      # role is a READER, not an applier): everything but GetObject* is denied to
      # all but the applier group; GetObject* is denied to all but appliers ∪
      # state_custody_readers.
      {
        Sid       = "DenyProtectedStateWriteExceptAppliers"
        Effect    = "Deny"
        Principal = "*"
        NotAction = local.state_read_actions
        Resource  = local.internal_state_resources
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = local.state_custody_applier_arns
          }
        }
      },
      {
        Sid       = "DenyProtectedStateReadExceptAppliersAndReaders"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.state_read_actions
        Resource  = local.internal_state_resources
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = concat(local.state_custody_applier_arns, local.state_custody_reader_arns)
          }
        }
      }],
      # Externally-APPLIED keys: exactly the roles listed for that key, nobody
      # else — not this repo's appliers either (round-17 L2/L3/L4 MAJOR: the
      # other repo's Atlantis applies eks-mgmt; a devbox re-apply from a
      # pre-deletion checkout is the split-brain this ADR exists to prevent).
      # The other repo's roles are exempt HERE and only here, so they never
      # reach the spokes, US or global/ state.
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
            "aws:PrincipalArn" = local.external_state_applier_arns[key]
          }
        }
      }],
      # Externally-READ keys (the frozen shared/ output contract, ADR-003): two
      # statements per key. Everything but GetObject* is denied to non-appliers
      # of this repo; GetObject* is denied to everyone who is neither one of
      # this repo's appliers nor a listed reader. round-16 denied the read too
      # and would have broken the other repo's every plan (round-17 CRITICAL).
      [for i, key in sort(keys(var.external_state_readers)) : {
        Sid       = "DenySharedStateWriteExceptAppliers${i}"
        Effect    = "Deny"
        Principal = "*"
        NotAction = local.state_read_actions
        Resource = [
          "${aws_s3_bucket.terraform_state.arn}/${key}",
          "${aws_s3_bucket.terraform_state.arn}/env:/*/${key}",
        ]
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = local.state_custody_applier_arns
          }
        }
      }],
      [for i, key in sort(keys(var.external_state_readers)) : {
        Sid       = "DenySharedStateReadExceptAppliersAndReaders${i}"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.state_read_actions
        Resource = [
          "${aws_s3_bucket.terraform_state.arn}/${key}",
          "${aws_s3_bucket.terraform_state.arn}/env:/*/${key}",
        ]
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = concat(local.state_custody_applier_arns, local.state_custody_reader_arns, local.external_state_reader_arns[key])
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

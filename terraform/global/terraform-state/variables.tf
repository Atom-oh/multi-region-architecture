variable "region" {
  description = "AWS region for the S3 bucket and DynamoDB table"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket to store Terraform state files"
  type        = string
  default     = "multi-region-mall-terraform-state"
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "multi-region-mall-terraform-locks"
}

variable "protected_state_keys" {
  description = <<-EOT
    State object keys (bucket-relative, S3 wildcards allowed) that only the
    principals in `state_custody_appliers` may touch. The `env:/<workspace>/<key>`
    variant of every key is added automatically (Terraform workspaces store
    state under the bucket-root env:/ prefix, not under the key's own prefix).
    Set to [] to create no bucket policy at all.

    This covers every layer this repo owns, `global/*`, and the eks-mgmt key
    that AWS-Demo-Platform owns but stores in this bucket (ADR-003). It is
    deliberately NOT a per-role map any more: a key→denied-role map is a
    denylist, and a denylist is fail-open toward every principal it does not
    name — see `state_custody_appliers`.
  EOT
  type        = list(string)
  default = [
    "production/ap-northeast-2/shared/terraform.tfstate",
    "production/ap-northeast-2/eks-mgmt/terraform.tfstate",
    "production/ap-northeast-2/eks-az-a/terraform.tfstate",
    "production/ap-northeast-2/eks-az-c/terraform.tfstate",
    "production/us-east-1/*",
    "production/us-west-2/*",
    "global/*",
  ]
}

variable "state_custody_appliers" {
  description = <<-EOT
    ALLOWLIST of IAM role names (path included, `*` allowed) in this account
    whose sessions may read/write every key in `protected_state_keys` and
    mutate this bucket's own policy — THIS repo's appliers. Appliers that
    belong to another repo and may touch only the one key that repo owns go
    in `external_state_appliers` instead (round-16 review L2/L5 MAJOR: a
    single flat list gave the other repo's Atlantis access to this repo's
    shared/ and US state, contradicting the "applier of a layer" claim). The bucket policy denies `s3:*` on those keys — and
    PutBucketPolicy & friends on the bucket — to every principal whose
    `aws:PrincipalArn` matches none of these (StringNotLike). Role NAMES, not
    ARNs: main.tf prefixes the account from data.aws_caller_identity so no
    account ID is committed to this public repo.

    Why an allowlist (round-13/14 review CRITICAL-2, 3/3 models, confirmed):
    the previous denylist named mall-apne2-mgmt-ci-runner's role ARN. That
    role can become a *different* principal ARN through its own
    `sts:AssumeRole role/cdk-*` and `iam:PassRole role/* (ecs-tasks)` +
    `ecs:RunTask` grants, and a Deny keyed on the listed ARN never matches
    those sessions. An allowlist denies every principal it does not name, so
    a pivot session is denied by construction. The runner role is therefore
    deliberately absent below — do not add it.

    ⚠ Self-lockout is the failure mode of an allowlist: a missing applier
    blocks that layer's next apply until a listed principal (or the account
    root, which can always PutBucketPolicy on its own bucket) fixes the list.
    CloudTrail S3 data events are not enabled in this account, so this list
    was assembled from the roles that exist in the account, not from access
    logs — confirm it against reality before every apply that changes it
    (ADR-003: the applier enumeration is a human decision, not an inference).
    An empty list is refused by a precondition on the policy resource rather
    than turned into a deny-everyone policy.
  EOT
  type        = list(string)
  default = [
    # This repo's layers, applied by humans/agents on the mgmt-vpc devbox
    # (code-server EC2 instance profile) — what `aws sts get-caller-identity`
    # returns for every plan/apply run from that box.
    "mgmt-vpc-VSCode-Role",
    "VSCodeAdminRole",
    # Human break-glass: IAM Identity Center AdministratorAccess permission set.
    # The trailing hash is regenerated whenever the permission set is
    # re-provisioned, so it is wildcarded — pinning it would silently lock the
    # only human recovery path out after routine SSO maintenance.
    "aws-reserved/sso.amazonaws.com/ap-northeast-2/AWSReservedSSO_AdministratorAccess_*",
  ]
}

variable "state_custody_readers" {
  description = <<-EOT
    READ-ONLY allowlist for this repo's own keys (every protected key that is
    not externally applied): IAM role names that may `s3:GetObject`/
    `GetObjectVersion` but never write. This is the CI `plan` path —
    github-actions-role reads state and takes the DynamoDB lock but no CI
    apply exists in this repo (every apply is a human on the devbox). round-17
    still had it in `state_custody_appliers`, i.e. exempt from the write Deny,
    which contradicted the "CI plan path, not applier" correction and left no
    resource-policy line of defence if its identity policy ever widened
    (round-18 review L2/L3 MAJOR). Same shape as `external_state_readers`.
  EOT
  type        = list(string)
  default = [
    # modules/security/iam/github-actions.tf. Its identity policy separately
    # denies the eks-mgmt key (defense-in-depth) — and that key is externally
    # applied, so this list does not reach it anyway.
    "github-actions-role",
  ]
}

variable "external_state_appliers" {
  description = <<-EOT
    Per-key allowlist for state objects another repo owns but stores in this
    bucket: protected key -> the COMPLETE list of IAM role names that may
    touch THAT key. `state_custody_appliers` is NOT added to it (round-17
    review L2/L3/L4 MAJOR: this repo's devbox roles have no reason to write
    the eks-mgmt layer's state — that layer is applied by the other repo's
    Atlantis — and letting them keeps the "re-apply from a pre-deletion
    checkout" split-brain path open). If a break-glass identity should keep
    access to an external key, list it here explicitly; the default keeps the
    SSO administrator permission set as the one human recovery path and
    records that choice in ADR-003. Keys here must also appear in
    `protected_state_keys` (a precondition checks it).
  EOT
  type        = map(list(string))
  default = {
    # ADR-003: infra/eks-mgmt is applied by that repo's Atlantis; its
    # terraformer role is the other identity that repo uses for state. The
    # SSO admin entry is the human break-glass (ADR-003 round-17 decision).
    "production/ap-northeast-2/eks-mgmt/terraform.tfstate" = [
      "AtlantisIRSARole",
      "DemoPlatformTerraformer",
      "aws-reserved/sso.amazonaws.com/ap-northeast-2/AWSReservedSSO_AdministratorAccess_*",
    ]
  }
}

variable "external_state_readers" {
  description = <<-EOT
    Per-key READ-ONLY allowlist: protected key -> IAM role names outside this
    repo that may `s3:GetObject`/`GetObjectVersion` that key but not write it.
    This is the frozen cross-repo contract from ADR-003: AWS-Demo-Platform's
    infra/eks-mgmt reads six outputs from shared/ via terraform_remote_state.
    round-16 forgot it and denied that read outright — the first apply of the
    policy would have broken every plan in the other repo (round-17 review
    CRITICAL, confirmed). Writes to these keys stay with
    `state_custody_appliers` only. Keys must also be in `protected_state_keys`.

    ⚠ EXPIRY CONDITION (round-18 review MAJOR): `terraform_remote_state` reads
    the WHOLE object, not six outputs, and shared/ state carries Aurora and
    DocumentDB master passwords in plaintext today. This grant therefore hands
    the listed roles those secrets — far less than the no-policy state before
    this PR (whole bucket read/write) and the exposed passwords were rotated
    2026-08-19, but it is a secret grant nonetheless. It is to be re-reviewed
    and narrowed (or removed in favour of a sanitized handoff — dedicated
    output-only state or SSM parameters) when ADR-003 follow-up 0(a)
    `manage_master_user_password = true` lands and the plaintext leaves state.
  EOT
  type        = map(list(string))
  default = {
    "production/ap-northeast-2/shared/terraform.tfstate" = [
      "AtlantisIRSARole",
      "DemoPlatformTerraformer",
    ]
  }
}

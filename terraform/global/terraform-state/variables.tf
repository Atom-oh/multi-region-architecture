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

variable "state_custody_denials" {
  description = <<-EOT
    Bucket-policy Deny map: IAM role name (in this account) -> state object keys
    that role must not touch. The default is the production deny map below; set to {} explicitly to create no bucket policy at all.

    Use this for principals whose permissions are granted by a repo other than
    this one, where an identity-policy Deny cannot reach them — the mgmt cluster's
    CI runner role is the case this exists for. A resource-policy Deny beats any
    identity Allow, including AWS-managed FullAccess policies.
  EOT
  type        = map(list(string))
  default = {
    # Owned by AWS-Demo-Platform/infra/eks-mgmt, pod-identity-bound to every
    # self-hosted runner SA on the mgmt cluster, and carrying AmazonS3FullAccess
    # + ReadOnlyAccess. Runner pods run PR code, so they must not reach state:
    # shared/ carries Aurora and DocumentDB master passwords in plaintext.
    #
    # eks-mgmt's own key is denied too, not exempted (round-10 review MAJOR,
    # confirmed): the original reasoning for exempting "its own layer" — "that
    # repo owns and applies it" — conflates repo ownership with *this role's*
    # authorization. Per the ADR, mall-apne2-mgmt-ci-runner is the self-hosted
    # GitHub Actions runner role (bound to runner pods that execute PR code);
    # the actual apply path for infra/eks-mgmt is that repo's Atlantis, a
    # separate identity. ci_runner has no legitimate reason to read or write
    # its own layer's state either, so leaving that one key open kept exactly
    # the "state object with more than one writer" risk this whole bucket
    # policy exists to close — just narrowed to one key instead of six.
    "mall-apne2-mgmt-ci-runner" = [
      "production/ap-northeast-2/shared/terraform.tfstate",
      "production/ap-northeast-2/eks-mgmt/terraform.tfstate",
      "production/ap-northeast-2/eks-az-a/terraform.tfstate",
      "production/ap-northeast-2/eks-az-c/terraform.tfstate",
      "production/us-east-1/*",
      "production/us-west-2/*",
      "global/*",
    ]
  }
}

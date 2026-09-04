variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for TLS listener (*.atomai.click) in ap-northeast-2"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# The mgmt cluster trust inputs (mgmt_cluster_name, expected_mgmt_vpc_id,
# expected_mgmt_tags, mgmt_cluster_security_group_id) are deliberately NOT
# variables here. All five are read from shared/ outputs so the two spokes cannot
# be asked to trust different things — a guard released on one AZ and forgotten on
# the other is the failure this layout removes. See the Runbooks in ../README.md.

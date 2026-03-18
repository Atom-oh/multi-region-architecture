variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
}

variable "domain_name" {
  description = "Base domain name (e.g., atomai.click)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for CloudFront (*.atomai.click)"
  type        = string
}

variable "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL to associate (empty string to skip)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

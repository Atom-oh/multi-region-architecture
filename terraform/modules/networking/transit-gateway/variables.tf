terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "amazon_side_asn" {
  description = "Private Autonomous System Number (ASN) for the Amazon side of a BGP session"
  type        = number
  default     = 64512
}

variable "vpc_ids" {
  description = "List of VPC IDs to attach to the Transit Gateway"
  type        = list(string)
}

variable "attachment_subnet_ids" {
  description = "List of subnet ID lists for each VPC attachment"
  type        = list(list(string))
}

variable "peer_region" {
  description = "Region of the peer Transit Gateway for peering"
  type        = string
  default     = ""
}

variable "peer_transit_gateway_id" {
  description = "ID of the peer Transit Gateway for peering"
  type        = string
  default     = ""
}

variable "create_peering" {
  description = "Whether to create a Transit Gateway peering attachment"
  type        = bool
  default     = false
}

variable "peer_cidr_block" {
  description = "CIDR block of the peer VPC for cross-region routing"
  type        = string
  default     = ""
}

variable "private_route_table_ids" {
  description = "List of private subnet route table IDs for cross-region routes"
  type        = list(string)
  default     = []
}

variable "data_route_table_ids" {
  description = "List of data subnet route table IDs for cross-region routes"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

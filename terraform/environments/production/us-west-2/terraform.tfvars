environment                      = "production"
region                           = "us-west-2"
vpc_cidr                         = "10.1.0.0/16"
availability_zones               = ["us-west-2a", "us-west-2b", "us-west-2c"]
public_subnet_cidrs              = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnet_cidrs             = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]
data_subnet_cidrs                = ["10.1.21.0/24", "10.1.22.0/24", "10.1.23.0/24"]
eks_cluster_name                 = "multi-region-mall"
domain_name                      = "atomai.click"
route53_zone_id                  = "Z0123456789ABCDEFGHIJ"
acm_certificate_arn              = "arn:aws:acm:us-west-2:123456789012:certificate/yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
docdb_global_cluster_identifier  = "multi-region-mall-docdb"

tags = {
  Project = "multi-region-mall"
  Team    = "platform"
}

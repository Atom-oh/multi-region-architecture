environment                     = "production"
region                          = "us-east-1"
vpc_cidr                        = "10.0.0.0/16"
availability_zones              = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs             = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs            = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
data_subnet_cidrs               = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
acm_certificate_arn             = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
docdb_global_cluster_identifier = "multi-region-mall-docdb"

tags = {
  Project = "multi-region-mall"
  Team    = "platform"
}

environment = "production"
region      = "ap-northeast-2"

vpc_cidr           = "10.2.0.0/16"
availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]

public_subnet_cidrs  = ["10.2.1.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.16.0/20", "10.2.32.0/20"]
data_subnet_cidrs    = ["10.2.48.0/24", "10.2.49.0/24"]

domain_name     = "atomai.click"
route53_zone_id = "Z0123456789ABCDEFGHIJ"

eks_az_a_cluster_name = "mall-apne2-az-a"
eks_az_c_cluster_name = "mall-apne2-az-c"

acm_certificate_arn = "arn:aws:acm:ap-northeast-2:180294183052:certificate/d5f951df-418a-4124-8d06-e55a2079bd26"

docdb_global_cluster_identifier = "multi-region-mall-docdb"

tags = {
  Project = "multi-region-mall"
  Team    = "platform"
}

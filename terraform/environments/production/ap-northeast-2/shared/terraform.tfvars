environment = "production"
region      = "ap-northeast-2"

vpc_cidr           = "10.2.0.0/16"
availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]

public_subnet_cidrs  = ["10.2.1.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.16.0/20", "10.2.32.0/20"]
data_subnet_cidrs    = ["10.2.48.0/24", "10.2.49.0/24"]

domain_name     = "atomai.click"
route53_zone_id = "Z01703432E9KT1G1FIRFM"

eks_az_a_cluster_name = "mall-apne2-az-a"
eks_az_c_cluster_name = "mall-apne2-az-c"

acm_certificate_arn             = "arn:aws:acm:ap-northeast-2:123456789012:certificate/zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"
cloudfront_acm_certificate_arn  = "arn:aws:acm:us-east-1:180294183052:certificate/f6b6907a-5747-4039-967a-a8c7c73116a7"

grafana_nlb_dns_name = "k8s-monitori-grafanan-e4bd2ff4ba-389a84ff5b796d58.elb.ap-northeast-2.amazonaws.com"
grafana_nlb_zone_id  = "ZIBE1TIR4HY56"

argocd_nlb_dns_name = "k8s-argocd-argocdse-fe9eaff2f7-171f383396f46d49.elb.ap-northeast-2.amazonaws.com"
argocd_nlb_zone_id  = "ZIBE1TIR4HY56"

docdb_global_cluster_identifier = "multi-region-mall-docdb"

tags = {
  Project = "multi-region-mall"
  Team    = "platform"
}

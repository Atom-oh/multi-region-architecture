environment         = "production"
region              = "us-east-1"
domain_name         = "atomai.click"
route53_zone_id     = "Z0123456789ABCDEFGHIJ"
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
argocd_nlb_dns_name = "k8s-argocd-xxxxxxxxxx-xxxxxxxxxxxxxxxx.elb.us-east-1.amazonaws.com"
argocd_nlb_zone_id  = "Z0EXAMPLE1234567"

tags = {
  Project = "multi-region-mall"
  Team    = "platform"
}

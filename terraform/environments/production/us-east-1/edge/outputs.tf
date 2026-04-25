output "cloudfront_domain" {
  value = module.cloudfront.distribution_domain_name
}

output "cloudfront_distribution_arn" {
  value = module.cloudfront.distribution_arn
}

output "argocd_cloudfront_domain" {
  value = module.cloudfront_argocd.distribution_domain_name
}

output "grafana_cloudfront_domain" {
  value = module.cloudfront_grafana.distribution_domain_name
}

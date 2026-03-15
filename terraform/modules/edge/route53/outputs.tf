output "api_domain_name" {
  description = "The API internal domain name for latency-based routing"
  value       = "api-internal.${data.aws_route53_zone.main.name}"
}

output "health_check_ids" {
  description = "Map of region to health check IDs"
  value = {
    for region, health_check in aws_route53_health_check.regional : region => health_check.id
  }
}

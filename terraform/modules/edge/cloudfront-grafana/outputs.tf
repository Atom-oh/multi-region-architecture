output "distribution_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.grafana.domain_name
}

output "distribution_hosted_zone_id" {
  description = "Route53 zone ID for the CloudFront distribution"
  value       = aws_cloudfront_distribution.grafana.hosted_zone_id
}

output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.grafana.id
}

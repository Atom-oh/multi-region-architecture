output "distribution_id" {
  description = "The ID of the ArgoCD CloudFront distribution"
  value       = aws_cloudfront_distribution.argocd.id
}

output "distribution_arn" {
  description = "The ARN of the ArgoCD CloudFront distribution"
  value       = aws_cloudfront_distribution.argocd.arn
}

output "distribution_domain_name" {
  description = "The domain name of the ArgoCD CloudFront distribution"
  value       = aws_cloudfront_distribution.argocd.domain_name
}

output "distribution_hosted_zone_id" {
  description = "The hosted zone ID of the ArgoCD CloudFront distribution"
  value       = aws_cloudfront_distribution.argocd.hosted_zone_id
}

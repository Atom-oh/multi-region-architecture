output "domain_id" {
  description = "The unique identifier for the OpenSearch domain"
  value       = aws_opensearch_domain.this.domain_id
}

output "domain_arn" {
  description = "Amazon Resource Name (ARN) of the domain"
  value       = aws_opensearch_domain.this.arn
}

output "domain_endpoint" {
  description = "Domain-specific endpoint used to submit index, search, and data upload requests"
  value       = aws_opensearch_domain.this.endpoint
}

output "kibana_endpoint" {
  description = "Domain-specific endpoint for Kibana/OpenSearch Dashboards"
  value       = aws_opensearch_domain.this.dashboard_endpoint
}

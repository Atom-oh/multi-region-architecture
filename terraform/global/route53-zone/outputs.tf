output "zone_id" {
  description = "The ID of the Route53 hosted zone"
  value       = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "The name servers for the Route53 hosted zone"
  value       = aws_route53_zone.main.name_servers
}

output "nlb_arn" {
  description = "ARN of the NLB"
  value       = aws_lb.this.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB"
  value       = aws_lb.this.dns_name
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the NLB (for Route53 alias records)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group (used by k8s TargetGroupBinding)"
  value       = aws_lb_target_group.this.arn
}

output "transit_gateway_id" {
  description = "The ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.id
}

output "transit_gateway_arn" {
  description = "The ARN of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.arn
}

output "peering_attachment_id" {
  description = "The ID of the Transit Gateway peering attachment"
  value       = var.create_peering ? aws_ec2_transit_gateway_peering_attachment.peer[0].id : null
}

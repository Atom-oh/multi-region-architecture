#------------------------------------------------------------------------------
# Transit Gateway
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "main" {
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, {
    Name        = "${var.environment}-tgw"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# Transit Gateway VPC Attachments
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  count              = length(var.vpc_ids)
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = var.vpc_ids[count.index]
  subnet_ids         = var.attachment_subnet_ids[count.index]

  tags = merge(var.tags, {
    Name        = "${var.environment}-tgw-attachment-${count.index}"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# Transit Gateway Peering Attachment
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_peering_attachment" "peer" {
  count                   = var.create_peering ? 1 : 0
  transit_gateway_id      = aws_ec2_transit_gateway.main.id
  peer_region             = var.peer_region
  peer_transit_gateway_id = var.peer_transit_gateway_id

  tags = merge(var.tags, {
    Name        = "${var.environment}-tgw-peering"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# Transit Gateway Route Table
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.tags, {
    Name        = "${var.environment}-tgw-rt"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# Transit Gateway Route to Peer (when peering is enabled)
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route" "peer" {
  count                          = var.create_peering ? 1 : 0
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.peer[0].id
}

# ap-northeast-2b private subnet for the mall-apne2-mgmt cluster's Karpenter.
#
# WHY STANDALONE (not added to the vpc module's availability_zones list):
# The vpc module zips availability_zones <-> {public,private,data}_subnet_cidrs by
# count.index, so adding "ap-northeast-2b" there also creates a 2b *data* subnet.
# MSK consumes module.vpc.data_subnet_ids as client_subnets, and changing that list
# forces a destroy/recreate of the production MSK cluster. Karpenter only needs a
# *private* subnet (its EC2NodeClass subnetSelector is `Tier: private`), so we add
# just that here, leaving the module's 3-tier set — and MSK — untouched.
#
# Egress reuses the existing ap-northeast-2a NAT gateway (no new NAT gateway).

resource "aws_subnet" "private_apne2b" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.2.64.0/20"
  availability_zone = "ap-northeast-2b"

  tags = merge(var.tags, {
    Name                          = "${var.environment}-private-ap-northeast-2b"
    Environment                   = var.environment
    Tier                          = "private"
    "topology.kubernetes.io/zone" = "ap-northeast-2b"
  })
}

resource "aws_route_table" "private_apne2b" {
  vpc_id = module.vpc.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = module.vpc.nat_gateway_ids[0] # reuse ap-northeast-2a NAT (azs[0])
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-private-rt-ap-northeast-2b"
  })
}

resource "aws_route_table_association" "private_apne2b" {
  subnet_id      = aws_subnet.private_apne2b.id
  route_table_id = aws_route_table.private_apne2b.id
}

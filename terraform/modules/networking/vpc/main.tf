#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name        = "${var.environment}-igw"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# Public Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-public-${var.availability_zones[count.index]}"
    Environment = var.environment
    Tier        = "public"
  })
}

#------------------------------------------------------------------------------
# Private Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name                          = "${var.environment}-private-${var.availability_zones[count.index]}"
    Environment                   = var.environment
    Tier                          = "private"
    "topology.kubernetes.io/zone" = var.availability_zones[count.index]
  })
}

#------------------------------------------------------------------------------
# Data Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name        = "${var.environment}-data-${var.availability_zones[count.index]}"
    Environment = var.environment
    Tier        = "data"
  })
}

#------------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(var.tags, {
    Name        = "${var.environment}-nat-eip-${var.availability_zones[count.index]}"
    Environment = var.environment
  })

  depends_on = [aws_internet_gateway.main]
}

#------------------------------------------------------------------------------
# NAT Gateways (one per AZ)
#------------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name        = "${var.environment}-nat-${var.availability_zones[count.index]}"
    Environment = var.environment
  })

  depends_on = [aws_internet_gateway.main]
}

#------------------------------------------------------------------------------
# Public Route Table
#------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-public-rt"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#------------------------------------------------------------------------------
# Private Route Tables (one per AZ)
#------------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-private-rt-${var.availability_zones[count.index]}"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#------------------------------------------------------------------------------
# Data Route Tables (one per AZ)
#------------------------------------------------------------------------------
resource "aws_route_table" "data" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-data-rt-${var.availability_zones[count.index]}"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "data" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data[count.index].id
}

#------------------------------------------------------------------------------
# VPC Endpoint Security Group (for Interface Endpoints)
#------------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.environment}-vpc-endpoints-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPC Interface Endpoints"

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-vpc-endpoints-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# VPC Gateway Endpoint - S3
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.private[*].id, aws_route_table.data[*].id)

  tags = merge(var.tags, {
    Name        = "${var.environment}-s3-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - ECR API
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-ecr-api-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - ECR DKR
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-ecr-dkr-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - STS
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-sts-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - CloudWatch Logs
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-logs-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - SSM (Karpenter AMI discovery, CDK bootstrap)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-ssm-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - EC2 (Karpenter instance provisioning)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-ec2-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - EKS (kubelet → API server private access)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "eks" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.eks"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-eks-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - KMS (EBS encryption, Secrets decryption)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-kms-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - Secrets Manager (ExternalSecrets sync)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-secretsmanager-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - CloudFormation (CDK deploy)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "cloudformation" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.cloudformation"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-cloudformation-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - Bedrock Runtime (model inference)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = false # Cross-region calls (e.g. us-east-1) must route via NAT, not local endpoint

  tags = merge(var.tags, {
    Name        = "${var.environment}-bedrock-runtime-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - Bedrock (model management, AgentCore)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "bedrock" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.bedrock"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = false # Same reason — cross-region Bedrock calls need NAT path

  tags = merge(var.tags, {
    Name        = "${var.environment}-bedrock-endpoint"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# VPC Interface Endpoint - EKS Auth (Pod Identity token exchange)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "eks_auth" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.eks-auth"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-eks-auth-endpoint"
    Environment = var.environment
  })
}

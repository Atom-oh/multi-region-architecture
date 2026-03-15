#------------------------------------------------------------------------------
# ALB Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-alb-"
  vpc_id      = var.vpc_id
  description = "Security group for Application Load Balancer"

  tags = merge(var.tags, {
    Name        = "${var.environment}-alb-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere"
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.alb.id
  description       = "All traffic to VPC"
}

#------------------------------------------------------------------------------
# EKS Node Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "eks_node" {
  name_prefix = "${var.environment}-eks-node-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS worker nodes"

  tags = merge(var.tags, {
    Name        = "${var.environment}-eks-node-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_node_ingress_alb" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.eks_node.id
  description              = "All traffic from ALB"
}

resource "aws_security_group_rule" "eks_node_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.eks_node.id
  description       = "Node to node communication"
}

resource "aws_security_group_rule" "eks_node_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound traffic"
}

#------------------------------------------------------------------------------
# Aurora Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "aurora" {
  name_prefix = "${var.environment}-aurora-"
  vpc_id      = var.vpc_id
  description = "Security group for Aurora PostgreSQL"

  tags = merge(var.tags, {
    Name        = "${var.environment}-aurora-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "aurora_ingress_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.aurora.id
  description              = "PostgreSQL from EKS nodes"
}

#------------------------------------------------------------------------------
# DocumentDB Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "documentdb" {
  name_prefix = "${var.environment}-documentdb-"
  vpc_id      = var.vpc_id
  description = "Security group for DocumentDB"

  tags = merge(var.tags, {
    Name        = "${var.environment}-documentdb-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "documentdb_ingress_eks" {
  type                     = "ingress"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.documentdb.id
  description              = "MongoDB from EKS nodes"
}

#------------------------------------------------------------------------------
# ElastiCache Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "elasticache" {
  name_prefix = "${var.environment}-elasticache-"
  vpc_id      = var.vpc_id
  description = "Security group for ElastiCache Redis"

  tags = merge(var.tags, {
    Name        = "${var.environment}-elasticache-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "elasticache_ingress_eks" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.elasticache.id
  description              = "Redis from EKS nodes"
}

#------------------------------------------------------------------------------
# MSK Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "msk" {
  name_prefix = "${var.environment}-msk-"
  vpc_id      = var.vpc_id
  description = "Security group for MSK (Kafka)"

  tags = merge(var.tags, {
    Name        = "${var.environment}-msk-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "msk_ingress_plaintext" {
  type                     = "ingress"
  from_port                = 9092
  to_port                  = 9092
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.msk.id
  description              = "Kafka plaintext from EKS nodes"
}

resource "aws_security_group_rule" "msk_ingress_tls" {
  type                     = "ingress"
  from_port                = 9094
  to_port                  = 9094
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.msk.id
  description              = "Kafka TLS from EKS nodes"
}

resource "aws_security_group_rule" "msk_ingress_sasl" {
  type                     = "ingress"
  from_port                = 9096
  to_port                  = 9096
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.msk.id
  description              = "Kafka SASL from EKS nodes"
}

resource "aws_security_group_rule" "msk_ingress_zookeeper" {
  type                     = "ingress"
  from_port                = 2181
  to_port                  = 2181
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.msk.id
  description              = "ZooKeeper from EKS nodes"
}

#------------------------------------------------------------------------------
# OpenSearch Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "opensearch" {
  name_prefix = "${var.environment}-opensearch-"
  vpc_id      = var.vpc_id
  description = "Security group for OpenSearch"

  tags = merge(var.tags, {
    Name        = "${var.environment}-opensearch-sg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "opensearch_ingress_eks" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.opensearch.id
  description              = "HTTPS from EKS nodes"
}

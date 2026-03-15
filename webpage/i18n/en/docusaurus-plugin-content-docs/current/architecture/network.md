---
title: Network Architecture
sidebar_position: 3
---

# Network Architecture

The Multi-Region Shopping Mall network is designed based on a 3-tier VPC architecture. Each region has an independent VPC, and cross-region communication is handled through Transit Gateway Peering.

## VPC Design

### CIDR Block Allocation

| Region | VPC CIDR | Purpose |
|--------|----------|---------|
| us-east-1 | 10.0.0.0/16 | Primary Region |
| us-west-2 | 10.1.0.0/16 | Secondary Region |

### us-east-1 Subnet Configuration

```mermaid
flowchart TB
    subgraph VPC["VPC: 10.0.0.0/16"]
        subgraph AZ1["Availability Zone A"]
            Pub1[Public Subnet<br/>10.0.1.0/24]
            Priv1[Private Subnet<br/>10.0.11.0/24]
            Data1[Data Subnet<br/>10.0.21.0/24]
        end

        subgraph AZ2["Availability Zone B"]
            Pub2[Public Subnet<br/>10.0.2.0/24]
            Priv2[Private Subnet<br/>10.0.12.0/24]
            Data2[Data Subnet<br/>10.0.22.0/24]
        end

        subgraph AZ3["Availability Zone C"]
            Pub3[Public Subnet<br/>10.0.3.0/24]
            Priv3[Private Subnet<br/>10.0.13.0/24]
            Data3[Data Subnet<br/>10.0.23.0/24]
        end
    end

    IGW[Internet Gateway] --> Pub1 & Pub2 & Pub3
    Pub1 --> NAT1[NAT Gateway]
    Pub2 --> NAT2[NAT Gateway]
    Pub3 --> NAT3[NAT Gateway]
    NAT1 --> Priv1
    NAT2 --> Priv2
    NAT3 --> Priv3
```

| Tier | AZ-a | AZ-b | AZ-c | Purpose |
|------|------|------|------|---------|
| **Public** | 10.0.1.0/24 | 10.0.2.0/24 | 10.0.3.0/24 | ALB, NAT Gateway |
| **Private** | 10.0.11.0/24 | 10.0.12.0/24 | 10.0.13.0/24 | EKS Worker Nodes |
| **Data** | 10.0.21.0/24 | 10.0.22.0/24 | 10.0.23.0/24 | Aurora, DocumentDB, ElastiCache, MSK, OpenSearch |

### us-west-2 Subnet Configuration

| Tier | AZ-a | AZ-b | AZ-c | Purpose |
|------|------|------|------|---------|
| **Public** | 10.1.1.0/24 | 10.1.2.0/24 | 10.1.3.0/24 | ALB, NAT Gateway |
| **Private** | 10.1.11.0/24 | 10.1.12.0/24 | 10.1.13.0/24 | EKS Worker Nodes |
| **Data** | 10.1.21.0/24 | 10.1.22.0/24 | 10.1.23.0/24 | Aurora, DocumentDB, ElastiCache, MSK, OpenSearch |

## 3-Tier Architecture

```mermaid
flowchart TB
    Internet((Internet))

    subgraph PublicTier["Public Tier"]
        IGW[Internet Gateway]
        ALB[Application Load Balancer]
        NAT[NAT Gateway x3]
    end

    subgraph PrivateTier["Private Tier (EKS)"]
        EKS[EKS Worker Nodes]
        Pod1[Core Services]
        Pod2[User Services]
        Pod3[Business Services]
    end

    subgraph DataTier["Data Tier"]
        Aurora[(Aurora PostgreSQL)]
        DocDB[(DocumentDB)]
        Cache[(ElastiCache Valkey)]
        MSK[MSK Kafka]
        OS[(OpenSearch)]
    end

    Internet --> IGW --> ALB
    ALB --> EKS
    EKS --> Pod1 & Pod2 & Pod3
    Pod1 & Pod2 & Pod3 --> Aurora & DocDB & Cache & MSK & OS
    EKS --> NAT --> Internet
```

### Role by Tier

| Tier | Components | Internet Access | Inbound Traffic |
|------|------------|-----------------|-----------------|
| **Public** | ALB, NAT Gateway | Direct | Internet → ALB |
| **Private** | EKS Nodes, Pods | Via NAT Gateway | ALB → EKS |
| **Data** | All data stores | None | EKS → Data stores |

## Transit Gateway Peering

Transit Gateway Peering is used for cross-region communication.

```mermaid
flowchart LR
    subgraph USE1["us-east-1"]
        VPC1[VPC 10.0.0.0/16]
        TGW1[Transit Gateway]
        EKS1[EKS Cluster]
    end

    subgraph USW2["us-west-2"]
        VPC2[VPC 10.1.0.0/16]
        TGW2[Transit Gateway]
        EKS2[EKS Cluster]
    end

    VPC1 <--> TGW1
    VPC2 <--> TGW2
    TGW1 <-->|"TGW Peering<br/>Cross-Region"| TGW2

    EKS1 -.->|"Write Forwarding"| EKS2
    EKS2 -.->|"Write Forwarding"| EKS1
```

### Transit Gateway Route Tables

**us-east-1 TGW Route Table:**

| Destination | Target | Purpose |
|-------------|--------|---------|
| 10.0.0.0/16 | VPC Attachment | Local VPC |
| 10.1.0.0/16 | Peering Attachment | us-west-2 VPC |

**us-west-2 TGW Route Table:**

| Destination | Target | Purpose |
|-------------|--------|---------|
| 10.1.0.0/16 | VPC Attachment | Local VPC |
| 10.0.0.0/16 | Peering Attachment | us-east-1 VPC |

### Terraform Configuration

```hcl
# us-east-1 Transit Gateway
resource "aws_ec2_transit_gateway" "use1" {
  provider = aws.us-east-1

  description                     = "Multi-region TGW us-east-1"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name = "multi-region-tgw-use1"
  }
}

# us-west-2 Transit Gateway
resource "aws_ec2_transit_gateway" "usw2" {
  provider = aws.us-west-2

  description                     = "Multi-region TGW us-west-2"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name = "multi-region-tgw-usw2"
  }
}

# Transit Gateway Peering
resource "aws_ec2_transit_gateway_peering_attachment" "use1_usw2" {
  provider = aws.us-east-1

  peer_region             = "us-west-2"
  peer_transit_gateway_id = aws_ec2_transit_gateway.usw2.id
  transit_gateway_id      = aws_ec2_transit_gateway.use1.id

  tags = {
    Name = "tgw-peering-use1-usw2"
  }
}
```

## Security Groups

### Security Group Configuration by Service

```mermaid
flowchart TB
    Internet((Internet)) -->|443| ALB_SG

    subgraph SGs["Security Groups"]
        ALB_SG[ALB SG<br/>Inbound: 443]
        EKS_SG[EKS Node SG<br/>Inbound: ALB]
        Aurora_SG[Aurora SG<br/>Inbound: 5432]
        DocDB_SG[DocumentDB SG<br/>Inbound: 27017]
        Cache_SG[ElastiCache SG<br/>Inbound: 6379]
        MSK_SG[MSK SG<br/>Inbound: 9096]
        OS_SG[OpenSearch SG<br/>Inbound: 443, 9200]
    end

    ALB_SG -->|"8080"| EKS_SG
    EKS_SG -->|"5432"| Aurora_SG
    EKS_SG -->|"27017"| DocDB_SG
    EKS_SG -->|"6379"| Cache_SG
    EKS_SG -->|"9096"| MSK_SG
    EKS_SG -->|"443,9200"| OS_SG
```

### Security Group Details

#### ALB Security Group

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Inbound | TCP | 443 | 0.0.0.0/0 | HTTPS traffic |
| Inbound | TCP | 80 | 0.0.0.0/0 | HTTP (redirect) |
| Outbound | TCP | 8080 | EKS SG | Service forwarding |

#### EKS Node Security Group

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Inbound | TCP | 8080 | ALB SG | Service traffic |
| Inbound | TCP | 443 | EKS Control Plane | API Server |
| Inbound | TCP | 10250 | EKS Control Plane | Kubelet |
| Inbound | All | All | Self | Pod-to-pod communication |
| Outbound | TCP | 5432 | Aurora SG | PostgreSQL |
| Outbound | TCP | 27017 | DocumentDB SG | MongoDB |
| Outbound | TCP | 6379 | ElastiCache SG | Redis/Valkey |
| Outbound | TCP | 9096 | MSK SG | Kafka SASL |
| Outbound | TCP | 443 | OpenSearch SG | OpenSearch HTTPS |
| Outbound | TCP | 443 | 0.0.0.0/0 | AWS APIs, ECR |

#### Aurora PostgreSQL Security Group

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Inbound | TCP | 5432 | EKS SG | Application access |
| Inbound | TCP | 5432 | 10.0.0.0/16 | Intra-region access |
| Inbound | TCP | 5432 | 10.1.0.0/16 | Cross-region replication |

#### DocumentDB Security Group

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Inbound | TCP | 27017 | EKS SG | Application access |
| Inbound | TCP | 27017 | 10.0.0.0/16 | Intra-region access |
| Inbound | TCP | 27017 | 10.1.0.0/16 | Cross-region replication |

#### ElastiCache Valkey Security Group

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Inbound | TCP | 6379 | EKS SG | Application access |
| Inbound | TCP | 6379 | Self | Intra-cluster communication |

#### MSK Kafka Security Group

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Inbound | TCP | 9096 | EKS SG | SASL/SCRAM authentication |
| Inbound | TCP | 9092 | EKS SG | Plaintext (internal) |
| Inbound | TCP | 2181 | EKS SG | Zookeeper |
| Inbound | TCP | 9096 | 10.0.0.0/16 | Intra-region access |
| Inbound | TCP | 9096 | 10.1.0.0/16 | MSK Replicator |

#### OpenSearch Security Group

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Inbound | TCP | 443 | EKS SG | HTTPS API |
| Inbound | TCP | 9200 | EKS SG | REST API |
| Inbound | TCP | 9300 | Self | Inter-node communication |

## NAT Gateway

Independent NAT Gateways are placed in each AZ for high availability.

```mermaid
flowchart TB
    subgraph AZ_A["AZ-a"]
        NAT1[NAT Gateway]
        EIP1[Elastic IP]
        Priv1[Private Subnet]
    end

    subgraph AZ_B["AZ-b"]
        NAT2[NAT Gateway]
        EIP2[Elastic IP]
        Priv2[Private Subnet]
    end

    subgraph AZ_C["AZ-c"]
        NAT3[NAT Gateway]
        EIP3[Elastic IP]
        Priv3[Private Subnet]
    end

    EIP1 --> NAT1
    EIP2 --> NAT2
    EIP3 --> NAT3

    Priv1 -->|"0.0.0.0/0"| NAT1
    Priv2 -->|"0.0.0.0/0"| NAT2
    Priv3 -->|"0.0.0.0/0"| NAT3

    NAT1 & NAT2 & NAT3 --> IGW[Internet Gateway]
```

### NAT Gateway Pros and Cons

| Configuration | Advantages | Disadvantages |
|---------------|------------|---------------|
| 1 NAT per AZ | AZ failure isolation, no cross-AZ traffic | Increased cost (3x) |
| Single NAT | Cost savings | Single Point of Failure |

Current configuration: **1 NAT Gateway per AZ** (high availability priority)

## VPC Endpoints

VPC Endpoints are configured to allow Private subnets to access AWS services.

```mermaid
flowchart LR
    subgraph Private["Private Subnet"]
        EKS[EKS Pods]
    end

    subgraph Endpoints["VPC Endpoints"]
        S3GW[S3 Gateway]
        ECR_API[ECR API]
        ECR_DKR[ECR Docker]
        STS[STS]
        CW[CloudWatch]
        SM[Secrets Manager]
        KMS[KMS]
    end

    subgraph AWS["AWS Services"]
        S3[(S3)]
        ECR[(ECR)]
        STS_SVC[STS]
        CW_SVC[CloudWatch]
        SM_SVC[Secrets Manager]
        KMS_SVC[KMS]
    end

    EKS --> S3GW --> S3
    EKS --> ECR_API & ECR_DKR --> ECR
    EKS --> STS --> STS_SVC
    EKS --> CW --> CW_SVC
    EKS --> SM --> SM_SVC
    EKS --> KMS --> KMS_SVC
```

### Endpoint Types

| Endpoint | Type | Service | Purpose |
|----------|------|---------|---------|
| S3 | **Gateway** | com.amazonaws.region.s3 | Object storage |
| ECR API | Interface | com.amazonaws.region.ecr.api | Image metadata |
| ECR DKR | Interface | com.amazonaws.region.ecr.dkr | Image download |
| STS | Interface | com.amazonaws.region.sts | IAM role assumption |
| CloudWatch Logs | Interface | com.amazonaws.region.logs | Log delivery |
| Secrets Manager | Interface | com.amazonaws.region.secretsmanager | Secret retrieval |
| KMS | Interface | com.amazonaws.region.kms | Encryption keys |

### Gateway vs Interface Endpoint

| Characteristic | Gateway Endpoint | Interface Endpoint |
|----------------|-----------------|-------------------|
| **Cost** | Free | Hourly + data processing |
| **Supported Services** | S3, DynamoDB only | Most AWS services |
| **Network** | Route table modification | ENI creation (Private IP) |
| **DNS** | Uses public DNS | Private DNS supported |

### Terraform Configuration

```hcl
# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id,
    aws_route_table.private_c.id,
  ]

  tags = {
    Name = "s3-gateway-endpoint"
  }
}

# ECR API Interface Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
    aws_subnet.private_c.id,
  ]

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "ecr-api-endpoint"
  }
}

# Secrets Manager Interface Endpoint
resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
    aws_subnet.private_c.id,
  ]

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "secrets-manager-endpoint"
  }
}
```

## Network Flow Summary

```mermaid
flowchart TB
    User[User] -->|HTTPS| CF[CloudFront]
    CF -->|HTTPS| R53[Route 53]
    R53 -->|Latency Routing| ALB1[ALB us-east-1]
    R53 -->|Latency Routing| ALB2[ALB us-west-2]

    subgraph USE1["us-east-1 VPC"]
        ALB1 -->|8080| EKS1[EKS Pods]
        EKS1 -->|5432| Aurora1[(Aurora)]
        EKS1 -->|27017| DocDB1[(DocumentDB)]
        EKS1 -->|6379| Cache1[(ElastiCache)]
        EKS1 -->|9096| MSK1[MSK]
        EKS1 -->|443| OS1[(OpenSearch)]
        EKS1 -->|VPC Endpoint| AWS1[AWS Services]
    end

    subgraph USW2["us-west-2 VPC"]
        ALB2 -->|8080| EKS2[EKS Pods]
        EKS2 -->|5432| Aurora2[(Aurora)]
        EKS2 -->|27017| DocDB2[(DocumentDB)]
        EKS2 -->|6379| Cache2[(ElastiCache)]
        EKS2 -->|9096| MSK2[MSK]
        EKS2 -->|443| OS2[(OpenSearch)]
        EKS2 -->|VPC Endpoint| AWS2[AWS Services]
    end

    EKS1 <-.->|TGW Peering| EKS2
```

## Next Steps

- [Data Architecture](./data) - Network configuration for data stores
- [Security](./security) - WAF, Security Group detailed rules

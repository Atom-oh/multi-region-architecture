---
sidebar_position: 3
title: Network Architecture
description: VPC 설계, 서브넷 구조, VPC Endpoints
---

# Network Architecture

## VPC Design

각 리전에 독립된 VPC가 배포되며, **3-tier 서브넷 구조**(Public / Private / Data)를 사용합니다. AZ별 NAT Gateway를 두어 단일 AZ 장애 시에도 다른 AZ의 아웃바운드 트래픽이 영향받지 않습니다.

| 구분 | us-east-1 | us-west-2 |
|------|-----------|-----------|
| **VPC CIDR** | `10.0.0.0/16` | `10.1.0.0/16` |
| **AZs** | us-east-1a, 1b | us-west-2a, 2b |
| **Public Subnets** | /24 × 2 (NLB, NAT GW) | /24 × 2 |
| **Private Subnets** | /24 × 2 (EKS Pods) | /24 × 2 |
| **Data Subnets** | /24 × 2 (RDS, DocDB, Cache) | /24 × 2 |
| **NAT Gateway** | 2 (AZ별 1개) | 2 (AZ별 1개) |
| **Transit Gateway** | Yes | Planned |

### Subnet Tiers

- **Public**: NLB, NAT Gateway 배치. Internet Gateway 연결.
- **Private**: EKS 워커 노드, Pod 네트워크. NAT Gateway를 통한 아웃바운드.
- **Data**: RDS, DocumentDB, ElastiCache, MSK, OpenSearch. NAT Gateway를 통한 아웃바운드.

### Route Tables

- AZ별 독립 Route Table (Private, Data 각각)
- 각 AZ의 NAT Gateway를 통한 `0.0.0.0/0` 라우팅
- Transit Gateway route는 peer VPC CIDR (`10.1.0.0/16`)용

## VPC Endpoints

비용 절감과 보안을 위해 주요 AWS 서비스에 대한 VPC Endpoint를 설정합니다.

| Endpoint | Type | 용도 |
|----------|------|------|
| **S3** | Gateway | ECR 이미지, Tempo traces, Analytics data |
| **ECR API** | Interface | 컨테이너 이미지 Pull (API 호출) |
| **ECR DKR** | Interface | 컨테이너 이미지 Pull (Docker 프로토콜) |
| **STS** | Interface | IRSA 토큰 교환 |
| **CloudWatch Logs** | Interface | OTel Collector 로그 전송 |

### VPC Endpoint Security Group

```hcl
# Interface Endpoints용 SG
ingress {
  description = "HTTPS from VPC"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr]  # VPC CIDR만 허용
}
```

:::tip
Gateway Endpoint(S3)는 무료이며 Route Table에 추가됩니다. Interface Endpoint는 시간당 과금되지만, NAT Gateway를 통한 외부 통신 비용을 절감합니다.
:::

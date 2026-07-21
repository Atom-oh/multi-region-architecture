---
sidebar_position: 5
title: Network Design
description: VPC, 서브넷, 보안 그룹 — /20 Private 서브넷, NAT per AZ
---

# Network Design

## VPC & Subnets

| Subnet | AZ-A (ap-northeast-2a) | AZ-C (ap-northeast-2c) | Size |
|--------|------------------------|------------------------|------|
| **Public** | `10.2.1.0/24` | `10.2.3.0/24` | 256 IPs |
| **Private** | `10.2.16.0/20` | `10.2.32.0/20` | **4,096 IPs** |
| **Data** | `10.2.48.0/24` | `10.2.49.0/24` | 256 IPs |

:::tip Private /20
기존 US 리전의 /24(256 IPs)와 달리 **/20(4,096 IPs)**을 사용합니다. Karpenter가 AZ 내에서만 노드를 프로비저닝하므로 단일 AZ에서 충분한 IP 공간이 필요합니다. /24에서는 노드 ~50개 미만으로 제한됩니다.
:::

### CIDR Comparison (US vs Korea)

| 리전 | VPC CIDR | Private Subnet | Size |
|------|----------|----------------|------|
| us-east-1 | `10.0.0.0/16` | /24 | 256 IPs |
| us-west-2 | `10.1.0.0/16` | /24 | 256 IPs |
| **ap-northeast-2** | `10.2.0.0/16` | **/20** | **4,096 IPs** |

### AZ-B Reserved

AZ-B(ap-northeast-2b)는 현재 미사용이지만, CIDR 번호 체계에서 B에 해당하는 블록을 비워두어 향후 확장에 대비합니다.

## 3-Tier Subnet Architecture

```
                      VPC 10.2.0.0/16
                           │
    ┌──────────────────────┼──────────────────────┐
    │ AZ-A (2a)            │                AZ-C (2c) │
    │                      │                      │
    │ Public: 10.2.1.0/24  │  Public: 10.2.3.0/24 │
    │   └── NLB-A          │    └── NLB-C          │
    │   └── NAT GW-A       │    └── NAT GW-C       │
    │                      │                      │
    │ Private: 10.2.16.0/20│  Private: 10.2.32.0/20│
    │   └── EKS mall-apne2-│    └── EKS mall-apne2-│
    │       az-a nodes     │        az-c nodes     │
    │                      │                      │
    │ Data: 10.2.48.0/24   │  Data: 10.2.49.0/24  │
    │   └── Aurora, DocDB  │    └── Aurora, DocDB  │
    │   └── ElastiCache    │    └── ElastiCache    │
    │   └── MSK, OpenSearch│    └── MSK, OpenSearch│
    └──────────────────────┴──────────────────────┘
```

## NAT Gateway

VPC 모듈에서 AZ별 NAT Gateway를 생성합니다. 각 AZ의 Private 서브넷 트래픽은 해당 AZ의 NAT GW를 통해 외부로 나갑니다 — cross-AZ NAT 트래픽이 발생하지 않습니다.

| AZ | NAT Gateway | EIP | Route Table |
|----|-------------|-----|-------------|
| AZ-A | `nat-gw-2a` | Allocated | Private-2a → nat-gw-2a |
| AZ-C | `nat-gw-2c` | Allocated | Private-2c → nat-gw-2c |

## VPC Endpoints

VPC 모듈에서 S3 Gateway와 Interface endpoints를 생성합니다:

| Endpoint | Type | 용도 |
|----------|------|------|
| S3 | Gateway | ECR image pull, Tempo S3 backend |
| ECR API | Interface | Container image metadata |
| ECR DKR | Interface | Container image pull |
| STS | Interface | IRSA token exchange |
| CloudWatch Logs | Interface | OTel Collector log export |

## Security Groups

Shared layer에서 생성한 SG를 양쪽 EKS 클러스터가 공유합니다. 두 클러스터 모두 같은 VPC 내에 있으므로 하나의 SG 세트로 관리 가능합니다.

| SG | Inbound Source | 용도 |
|----|---------------|------|
| **ALB SG** | CloudFront Prefix List (80-443) | ALB Ingress |
| **NLB SG** | CloudFront Prefix List | NLB (api-internal) |
| **EKS SG** | VPC CIDR only | EKS node communication |
| **Aurora SG** | EKS Node SG | Aurora access |
| **DocumentDB SG** | EKS Node SG | DocumentDB access |
| **ElastiCache SG** | EKS Node SG | Valkey access |
| **MSK SG** | EKS Node SG | Kafka access |
| **OpenSearch SG** | EKS Node SG | OpenSearch access |
| **Istio east-west SG** | VPC CIDR only (15008-15017 range) | Cross-cluster mesh (az-a ↔ az-c) |

:::danger Zero Public Exposure
US 리전과 동일한 보안 정책을 적용합니다. 모든 SG는 Terraform으로 관리되며, `0.0.0.0/0` inbound rule은 절대 생성하지 않습니다.
:::

## Istio Ambient East-West Gateway (Zone Failover)

az-a/az-c는 완전히 분리된 클러스터라, 클러스터 전체 장애는 상단의 multi-AZ NLB weighted routing으로 이미 커버됩니다. 하지만 **부분 장애**(예: az-a의 `payment` 파드만 다운)는 커버되지 않았습니다 — `api-gateway`는 항상 자기 클러스터의 `*.svc.cluster.local`만 호출하기 때문입니다.

Istio ambient(멀티클러스터)를 두 클러스터에 설치해 이 문제를 해결합니다:

- **모델**: multi-network multicluster — 같은 VPC(`10.2.0.0/16`)에 있어도 ambient multicluster는 network 단위로만 통신을 지원하므로, az-a/az-c를 서로 다른 `network`(`az-a`/`az-c`)로, 하나의 `meshID`(`vellure-mesh-kr`)로 구성합니다.
- **East-west gateway**: 각 클러스터에 internal NLB 1개(`istio: eastwestgateway`), 위 표의 전용 SG로 보호됩니다. HBONE(mTLS 터널, 15008), istiod XDS(15012), admission webhook(15017).
- **범위**: `payment`, `order` Service에만 `istio.io/global: "true"` 라벨을 붙인 파일럿 — 전체 서비스로 확장은 검증 후.
- **원 문서**: `k8s/infra/istio-eastwest/README.md` (설치 매니페스트, 수동 remote-secret 부트스트랩 절차, 페일오버 검증 커맨드).

:::info Istio 버전
`1.30.1` (2026-05 릴리스) — Kubernetes 1.32~1.36을 공식 지원하며, 이 리전 EKS 클러스터의 1.36과 호환됩니다.
:::

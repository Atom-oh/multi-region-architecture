---
sidebar_position: 6
title: Compute
description: AZ별 EKS 클러스터, Karpenter, NLB 구성
---

# Compute

## EKS Clusters

### mall-apne2-az-a

| 속성 | 값 |
|------|-----|
| Cluster Name | `mall-apne2-az-a` |
| AZ | ap-northeast-2a only |
| Private Subnet | `private_subnet_ids[0]` — `10.2.16.0/20` |
| Bootstrap Nodes | t3.medium / t3a.medium |
| Role Suffix | `-apne2-az-a` |
| IRSA | ALB Controller, OTel Collector, Tempo |

**핵심:** 모든 리소스(EKS 노드, NLB, Pod)가 `ap-northeast-2a`에만 존재합니다. private_subnet_ids 중 index [0]만 사용하여 single-AZ 격리를 달성합니다.

### mall-apne2-az-c

| 속성 | 값 |
|------|-----|
| Cluster Name | `mall-apne2-az-c` |
| AZ | ap-northeast-2c only |
| Private Subnet | `private_subnet_ids[1]` — `10.2.32.0/20` |
| Bootstrap Nodes | t3.medium / t3a.medium |
| Role Suffix | `-apne2-az-c` |
| IRSA | ALB Controller, OTel Collector, Tempo |

AZ-A와 동일한 구조로 `ap-northeast-2c`에만 존재합니다.

## Karpenter per AZ

각 EKS 클러스터의 Karpenter EC2NodeClass는 해당 AZ의 서브넷만 선택하도록 **이중 안전장치**를 적용합니다.

### AZ-A EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: mall-apne2-az-a-node-group
  subnetSelectorTerms:
    - tags:
        Tier: private
        topology.kubernetes.io/zone: ap-northeast-2a   # 물리적 AZ 고정
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: mall-apne2-az-a         # 논리적 격리
  amiSelectorTerms:
    - alias: al2023@latest
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        iops: 3000
        throughput: 125
        encrypted: true
        deleteOnTermination: true
```

### AZ-C EC2NodeClass

```yaml
spec:
  role: mall-apne2-az-c-node-group
  subnetSelectorTerms:
    - tags:
        Tier: private
        topology.kubernetes.io/zone: ap-northeast-2c   # AZ-C만
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: mall-apne2-az-c         # AZ-C 전용 SG
  amiSelectorTerms:
    - alias: al2023@latest
```

:::tip 이중 AZ 고정
1. `topology.kubernetes.io/zone` 서브넷 태그로 **물리적 AZ 고정**
2. `karpenter.sh/discovery` SG 태그로 **논리적 격리**

NodePool의 `topology.kubernetes.io/zone` requirement도 추가하면 3중 안전장치가 됩니다.
:::

### NodePool Configuration

US 리전과 동일한 6개 NodePool을 각 AZ 클러스터에 배포합니다:

| NodePool | 용도 | Instance Types |
|----------|------|----------------|
| general | 범용 워크로드 | m5, m5a, m6i |
| critical | 시스템 컴포넌트 | m5, m5a |
| api-tier | API 서비스 | c5, c5a, c6i |
| worker-tier | 비동기 워커 | m5, m5a |
| batch-tier | 배치 작업 | m5, m5a |
| memory-tier | 메모리 집약 | r5, r5a, r6i |

## NLB per AZ

각 AZ에 독립 NLB를 배포합니다. Route53 Latency-based 또는 Weighted routing으로 트래픽을 분배합니다.

| 속성 | AZ-A NLB | AZ-C NLB |
|------|----------|----------|
| Public Subnet | `10.2.1.0/24` | `10.2.3.0/24` |
| TLS | ACM cert (`*.atomai.click`) | ACM cert (`*.atomai.click`) |
| SG | Shared NLB SG (CloudFront prefix list) | Shared NLB SG |
| Target | EKS mall-apne2-az-a pods | EKS mall-apne2-az-c pods |

```
Route53 (api-korea.atomai.click)
├── Latency/Weighted → NLB-A (AZ-A, Public Subnet 10.2.1.0/24)
│   └── → api-gateway pods (mall-apne2-az-a)
└── Latency/Weighted → NLB-C (AZ-C, Public Subnet 10.2.3.0/24)
    └── → api-gateway pods (mall-apne2-az-c)
```

## US 리전과의 차이점

| 항목 | US (Multi-Region) | Korea (Multi-AZ) |
|------|-------------------|-------------------|
| 클러스터 수 | 리전당 1 | AZ당 1 |
| 클러스터 이름 | `multi-region-mall` | `mall-apne2-az-a/c` |
| Private Subnet | /24 (256 IPs) | /20 (4,096 IPs) |
| Karpenter AZ | multi-AZ 분산 | single-AZ 고정 |
| EC2NodeClass role | `multi-region-mall-node-group` | `mall-apne2-az-a-node-group` / `az-c` |
| TopologySpreadConstraints | 활성 (cross-AZ 분산) | 제거 (단일 AZ) |

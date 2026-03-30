---
sidebar_position: 4
title: Compute Layer
description: EKS 클러스터, Karpenter NodePool, Addon 버전
---

# Compute Layer

## EKS Clusters

### us-east-1 — Primary

| 항목 | 값 |
|------|-----|
| Cluster Name | `multi-region-mall` |
| EKS Version | `v1.35` (v1.35.2-eks-f69f56f) |
| Bootstrap Nodes | 2× t3.medium / t3a.medium |
| App Nodes | ~14-15 (Karpenter managed) |
| Node IAM Role | `multi-region-mall-node-group` |
| Karpenter Role | `multi-region-mall-karpenter-controller` |

### us-west-2 — Secondary

| 항목 | 값 |
|------|-----|
| Cluster Name | `multi-region-mall` |
| EKS Version | `v1.35` (v1.35.2-eks-f69f56f) |
| Bootstrap Nodes | 2× t3.medium / t3a.medium |
| App Nodes | ~14-15 (Karpenter managed) |
| Node IAM Role | `multi-region-mall-node-group-us-west-2` |
| Karpenter Role | `...-karpenter-controller-us-west-2` |

### EKS Addon Versions

| Addon | Version | 비고 |
|-------|---------|------|
| VPC CNI | `v1.21.1` | eksbuild suffix differs by region |
| CoreDNS | `v1.13.2` | |
| kube-proxy | `v1.35.0` | |
| EBS CSI | `v1.56.0` | IRSA 필수 (1.35에서 IMDS 제한) |
| EFS CSI | `v2.3.0` | IRSA 필수 |

:::caution IAM Role 네이밍
us-east-1은 `role_name_suffix = ""` (접미사 없음) — 서픽스 컨벤션 이전에 생성됨. us-west-2는 `-us-west-2` 접미사 사용.
:::

## Karpenter v1.9

부트스트랩 노드 그룹(2× m5.large)은 시스템 워크로드(Karpenter, ArgoCD, CoreDNS)를 실행하고, 애플리케이션 노드는 Karpenter가 **6개 NodePool**을 통해 동적 프로비저닝합니다.

### NodePools

| NodePool | 용도 | Instance Types |
|----------|------|---------------|
| `general` | 일반 워크로드 | m5, m6i, m7i (mixed) |
| `critical` | 핵심 서비스 (API GW, Order) | c5, c6i (compute-optimized) |
| `api-tier` | API 계층 서비스 | m5, c5 (balanced) |
| `worker-tier` | 백그라운드 처리 | m5, r5 (general) |
| `batch-tier` | 배치 작업 | m5, c5 (spot 가능) |
| `memory-tier` | 메모리 집약 워크로드 | r5, r6i (memory-optimized) |

### EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  role: multi-region-mall-node-group  # IAM은 글로벌, 양 리전에서 동작
  subnetSelectorTerms:
    - tags:
        Tier: private
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: multi-region-mall
```

:::info Architecture
**amd64 only.** arm64(Graviton)는 Phase 2에서 도입 예정. EC2NodeClass는 `role: multi-region-mall-node-group`을 사용하며, IAM이 글로벌이므로 양쪽 리전에서 동작합니다.
:::

### Karpenter Requirements

- Instance profile IAM permissions
- SQS permissions (interruption handling)
- `karpenter.sh/nodepool` tag on subnets
- aws-auth ConfigMap에 node group role 등록
  - us-west-2: regional role **AND** global node-group role (Karpenter용)

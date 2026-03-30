---
sidebar_position: 2
title: Why Multi Independent AZ
description: Multi Independent AZ 패턴의 동기와 트레이드오프
---

# Why Multi Independent AZ

## 핵심 동기

### Blast Radius Isolation

단일 AZ 장애 시 해당 AZ의 EKS 클러스터만 영향을 받고, 다른 AZ의 클러스터는 완전히 독립적으로 동작합니다. 일반적인 multi-AZ EKS(단일 클러스터, 여러 AZ)보다 강한 격리 수준을 제공합니다.

| 장애 유형 | 일반 Multi-AZ EKS | Multi Independent AZ |
|-----------|-------------------|----------------------|
| AZ 전체 장애 | 클러스터 일부 노드 손실, 스케줄링 혼란 | 해당 AZ 클러스터만 격리, 다른 AZ 무영향 |
| 컨트롤 플레인 이슈 | 전체 클러스터 영향 | AZ별 독립 컨트롤 플레인 |
| 노드 스케일링 문제 | 클러스터 전체에 파급 | AZ 내에서만 영향 |

### Cross-AZ 비용 절감

AWS cross-AZ 데이터 전송 비용은 **$0.01/GB**입니다. AZ-local 데이터 접근으로 읽기 트래픽의 cross-AZ 전송을 제거하면, read-heavy 워크로드에서 **$500~2,000/월** 절감 가능합니다.

```
일반 Multi-AZ EKS:
  Pod(AZ-A) ──$0.01/GB──→ DB Reader(AZ-C)  ← cross-AZ 비용 발생!

Multi Independent AZ:
  Pod(AZ-A) ──$0.00──→ DB Reader(AZ-A)     ← AZ-local, 무료!
```

### Independent Scaling

AZ별 독립 Karpenter가 해당 AZ의 워크로드에 맞춰 독립적으로 노드를 스케일링합니다. AZ 간 워크로드 불균형이 있어도 각 AZ가 자체적으로 최적화됩니다.

### Canary Deployment

AZ-A에 먼저 배포 후 검증, AZ-C에 롤아웃하는 Blue/Green AZ 전략이 가능합니다. 리전 전체를 한번에 롤아웃하는 것보다 안전합니다.

## Trade-offs

### 추가 비용

| 항목 | 월 비용 |
|------|---------|
| EKS 클러스터 추가 (1개) | ~$73 |
| NLB 추가 (1개) | ~$20-30 |
| **합계** | **~$100/월** |

### 손익분기점

:::tip 손익분기점 계산
EKS 추가 비용 $73 / cross-AZ 비용 $0.01/GB = **7.3TB/월**

월 7.3TB 이상의 cross-AZ 읽기 트래픽이 있으면 2-cluster가 cost-effective합니다. 쇼핑몰의 상품 조회, 검색, 추천 등 read-heavy 특성을 감안하면 이 기준을 초과할 가능성이 높습니다.
:::

### 운영 복잡도

| 항목 | 영향 |
|------|------|
| Terraform state | 3개 (shared, eks-az-a, eks-az-c) — US의 1개보다 많음 |
| ArgoCD 클러스터 등록 | 2개 추가 등록 필요 |
| 모니터링 대시보드 | AZ별 분리 뷰 필요 |
| Deployment 파이프라인 | AZ 순차 롤아웃 가능 (장점이기도 함) |

## 대안 비교

### Option 1: Single Cluster + Topology-Aware Scheduling

- Kubernetes `topologySpreadConstraints`로 AZ 분산
- 비용 절감 없음 (cross-AZ 트래픽 여전히 발생)
- Blast radius: AZ 장애 시 클러스터 전체에 파급
- **적합**: 소규모, read-light 워크로드

### Option 2: Multi Independent AZ (현재 선택)

- AZ별 독립 EKS 클러스터
- AZ-local 데이터 접근으로 cross-AZ 비용 절감
- 강한 blast radius isolation
- **적합**: read-heavy, 고가용성 요구, 비용 최적화 필요

### Option 3: Multi-Region Expansion

- ap-northeast-2를 기존 Multi-Region에 3번째 리전으로 추가
- Aurora Global Cluster에 참여
- **부적합**: 한국 데이터 주권 고려, 독립 운영 필요

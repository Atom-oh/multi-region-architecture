---
sidebar_position: 10
title: Cost & Roadmap
description: 비용 분석, 손익분기점, 구현 로드맵
---

# Cost & Roadmap

## Cost Analysis

### 추가 비용 항목

| 항목 | 월 비용 | 비고 |
|------|---------|------|
| EKS 클러스터 추가 (1개) | **~$73** | $0.10/hr per cluster |
| NLB 추가 (1개) | ~$20-30 | 기본 요금 + LCU |
| NAT Gateway (이미 AZ별 존재) | $0 | Shared layer에서 생성 |
| **합계 추가** | **~$100/월** | |

### 절감 항목

| 항목 | 월 절감 | 조건 |
|------|---------|------|
| Cross-AZ 데이터 전송 (읽기) | **$500~2,000** | Read-heavy 워크로드, 트래픽 규모 의존 |
| Cross-AZ 데이터 전송 (Kafka) | $100~500 | rack-aware 소비로 브로커-컨슈머 로컬화 |

### 손익분기점

:::tip 손익분기점 계산
- EKS 추가 비용: $73/월
- Cross-AZ 전송 비용: $0.01/GB
- **손익분기점: 7.3TB/월** ($73 / $0.01)

월 7.3TB 이상의 cross-AZ 읽기 트래픽이 있으면 2-cluster 구조가 cost-effective합니다. 쇼핑몰의 상품 조회, 검색, 추천 등 read-heavy 특성을 감안하면 이 기준을 초과할 가능성이 높습니다.
:::

### TCO (Total Cost of Ownership)

Codex의 분석에 따르면:

| 시나리오 | 추가 비용 영향 |
|----------|--------------|
| 컴퓨트만 | +12~25% |
| 데이터 포함 | +4~12% |
| Read-heavy (>10TB/월) | **순절감** |

## Implementation Roadmap

| Phase | Week | Tasks | Status |
|-------|------|-------|--------|
| **1. Infrastructure** | Week 1 | TF shared/ (VPC, SGs, KMS, Data Stores) | Complete |
| | | TF eks-az-a/ + eks-az-c/ (EKS, NLB, IRSA) | Complete |
| **2. K8s Manifests** | Week 2 | overlays/ap-northeast-2/\{common, az-a, az-c\}/ | Complete |
| | | Karpenter EC2NodeClass + NodePool per AZ | Complete |
| | | ArgoCD ApplicationSet update | Complete |
| **3. App Code** | Week 2-3 | DB_WRITE_HOST / DB_READ_HOST_LOCAL support | Planned |
| | | ElastiCache RouteByLatency | Planned |
| | | Kafka CLIENT_RACK + KAFKA_BROKERS_LOCAL | Planned |
| **4. Verification** | Week 3 | terraform plan (all 3 layers) | Planned |
| | | kubectl kustomize build | Planned |
| | | Cross-AZ traffic monitoring | Planned |

## Phase 2 Optimization (Future)

| Priority | Item | 기대 효과 |
|----------|------|-----------|
| P1 | ARM64 (Graviton) 이미지 빌드 | 컴퓨트 비용 최대 40% 절감 |
| P1 | MSK Replicator (US ↔ Korea) | Cross-region 이벤트 동기화 |
| P2 | CloudFront + WAF for Korea | 한국 사용자 CDN 최적화 |
| P2 | Route53 Latency-based (Global) | 글로벌 트래픽 분산 |
| P3 | Aurora Global Cluster 참여 검토 | Cross-region DR (현재는 독립 클러스터) |

## Monitoring Checklist

배포 후 확인해야 할 항목:

- [ ] AZ-A / AZ-C 클러스터 각각 노드 프로비저닝 정상
- [ ] Cross-AZ 트래픽 모니터링 (VPC Flow Logs)
- [ ] AZ-local 읽기가 실제로 같은 AZ에서 처리되는지 확인
- [ ] Karpenter가 올바른 AZ에서만 노드 생성하는지 확인
- [ ] MSK rack-aware 소비가 동작하는지 확인 (consumer lag per AZ)
- [ ] OTel trace에 `aws.zone` attribute가 올바르게 첨부되는지 확인
- [ ] ArgoCD ApplicationSet이 양쪽 클러스터에 정상 배포되는지 확인

## Known Considerations

:::warning 운영 주의사항
1. **Terraform Apply 순서**: 반드시 `shared` → `eks-az-a` → `eks-az-c` 순서
2. **ArgoCD 등록**: 2개 클러스터를 각각 ArgoCD에 등록해야 함
3. **ConfigMap placeholders**: Terraform 적용 후 실제 엔드포인트로 교체 필요
4. **DocumentDB Instance EP**: 인스턴스 교체/failover 시 엔드포인트가 변경될 수 있음
5. **MSK server_properties**: `replica.selector.class` 설정이 MSK 모듈에 하드코딩 — 필요 시 모듈 업데이트
:::

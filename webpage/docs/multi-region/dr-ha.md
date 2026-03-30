---
sidebar_position: 10
title: DR & HA Strategy
description: Failover 전략, DR Automation, Known Gaps
---

# DR & HA Strategy

## Failover Components

| Component | Failover Method | RTO Target |
|-----------|----------------|------------|
| **Aurora Global** | Global Cluster Failover (managed) | < 1 min |
| **DocumentDB Global** | Lambda 자동 Failover (`dr-automation` 모듈) | < 5 min |
| **ElastiCache Global** | Global Datastore Failover | < 1 min |
| **MSK** | Independent clusters | N/A (RPO: unbounded) |
| **Route53** | Latency-based 자동 라우팅 전환 | < 60s (TTL) |
| **CloudFront** | Origin failover 미설정 (수동 전환) | Manual |

## DR Automation Module

`terraform/modules/dr-automation/`

### DocumentDB Failover Lambda

- **Function**: `production-docdb-failover`
- **Runtime**: Python 3.12
- **Timeout**: 300s
- **권한**: `rds:FailoverGlobalCluster`, `rds:DescribeGlobalClusters`, `sns:Publish`

```python
# Lambda가 수행하는 작업:
# 1. Global Cluster 상태 확인
# 2. us-west-2 클러스터를 새 Primary로 승격
# 3. SNS 알림 발송
```

### SNS Alerts

- **Topic**: `production-dr-alerts`
- **구독**: email → `ops@example.com`

### Configuration

```hcl
module "dr_automation" {
  enable_auto_failover = false  # 수동 승인 필요 (초기)

  docdb_global_cluster_id     = "production-docdb-global"
  docdb_target_cluster_id     = "production-docdb-global-us-west-2"
  elasticache_global_group_id = module.elasticache.global_replication_group_id
  elasticache_target_region   = "us-west-2"
  notification_email          = "ops@example.com"
}
```

## Known Gaps

:::danger Deep Research Audit 결과 (2026-03-24)

### Critical Issues
1. **us-west-2는 사실상 read-only** — 완전한 active-active가 아님
2. **MSK cross-region replication 미설정** — unbounded RPO
3. **CloudFront origin failover group 미설정**
4. **API 인증 없음** — Cognito 미들웨어 작업 중

### Performance
- 현재 RTO: **~15-20분** (목표 < 10분)
- Circuit breaker 미구현
- `service_client.py`의 Sequential HTTP 호출 (병렬화 필요)
- OTel 샘플링 미설정 (전량 수집)

### Security
- 3 Critical, 7 High, 8 Medium 취약점 발견
- Hardcoded DB password (`<YOUR_PASSWORD>`)
- IDOR 취약점 가능성
- Regex injection 위험
:::

## Improvement Roadmap

| Priority | Item | Status |
|----------|------|--------|
| P0 | Cognito API 인증 | In Progress |
| P0 | DB 비밀번호 Secrets Manager 전환 | Planned |
| P1 | CloudFront origin failover | Planned |
| P1 | MSK Replicator 설정 | Planned |
| P1 | Circuit breaker 구현 | Planned |
| P2 | OTel 샘플링 설정 | Planned |
| P2 | Origin Shield 활성화 | Planned |

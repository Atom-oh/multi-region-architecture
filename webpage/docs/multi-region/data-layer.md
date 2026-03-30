---
sidebar_position: 5
title: Data Layer
description: Aurora Global, DSQL, DocumentDB, ElastiCache, MSK, OpenSearch, S3
---

# Data Layer

## Replication Overview

| Data Store | Replication | us-east-1 Role | us-west-2 Role |
|------------|-------------|----------------|----------------|
| **Aurora PostgreSQL** | Global Database | Primary (Writer) | Secondary (Read + Write Fwd) |
| **Aurora DSQL** | — | Standalone | No cluster |
| **DocumentDB** | Global Cluster | Primary | Secondary |
| **ElastiCache (Valkey)** | Global Datastore | Primary | Secondary |
| **MSK (Kafka)** | Independent | Standalone | Standalone |
| **OpenSearch** | Independent | Standalone | Standalone |
| **S3** | CRR possible | Primary | Secondary |

## Aurora Global Database

| 속성 | 값 |
|------|-----|
| Engine | Aurora PostgreSQL `17.7` |
| Global Cluster | Write Forwarding 활성화 |
| us-east-1 | Writer 1 + Reader 1 (`db.r6g.large`) |
| us-west-2 | Reader 2 (Secondary Cluster) |
| Encryption | KMS CMK per region |
| Monitoring | Enhanced Monitoring 60s + Performance Insights |
| Backup | Primary 7-day retention, Daily 03:00-04:00 UTC |

**Endpoints:**
- us-east-1: `production-aurora-global-us-east-1.cluster-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com`
- us-west-2: `production-aurora-global-us-west-2.cluster-yyyyyyyyyyyy.us-west-2.rds.amazonaws.com`

```hcl
module "aurora" {
  source = "../../../../modules/data/aurora-global"

  is_primary                  = true  # us-east-1
  global_cluster_identifier   = ""    # Primary는 null
  enable_global_write_forwarding = true  # Secondary에서 활성화
  reader_count                = 2
}
```

## Aurora DSQL

Go 서비스(inventory, shipping)가 사용하는 서버리스 분산 SQL.

| 속성 | 값 |
|------|-----|
| 인증 | IAM 토큰 (`aws dsql generate-db-connect-admin-auth-token`) |
| IRSA | `production-dsql-access-us-east-1` |
| Endpoint | `xxxxxxxxxxxxxxxxxxxxxxxxxxxx.dsql.us-east-1.on.aws` |
| Go Dockerfile | `debian:bookworm-slim` (Alpine lacks CLI v2) |

:::warning DSQL 제약사항
- JSONB 미지원
- Foreign Key 미지원
- Advisory Lock 미지원
- `CREATE INDEX ASYNC` 필수
- us-west-2에는 DSQL 클러스터 없음 (mock fallback)
:::

## DocumentDB Global Cluster

| 속성 | 값 |
|------|-----|
| Engine | DocumentDB `8.0.0` (MongoDB 호환) |
| Global Cluster ID | `production-docdb-global` |
| us-east-1 (Primary) | `production-docdb-global-primary` (2 instances, db.r6g.large) |
| us-west-2 (Secondary) | `production-docdb-global-us-west-2` (2 instances) |
| 연결 서비스 | 7개 Python 서비스 (motor + pymongo\<4.8) |
| 인증 | SCRAM-SHA-1, TLS (tlsAllowInvalidCertificates=true) |

:::danger DocumentDB 주의사항
- **5.0→8.0 in-place 업그레이드 불가** — destroy + recreate 필요
- **Global Cluster 생성 순서**: standalone primary 생성 → `create-global-cluster --source-db-cluster-identifier`로 연결 → secondary 추가
- us-east-1 primary는 `production-docdb-global-primary` (스냅샷 복원으로 비표준 이름)
:::

## ElastiCache Global Datastore (Valkey)

| 속성 | 값 |
|------|-----|
| Engine | Valkey 7 |
| us-east-1 | `cache.r7g.medium`, 2 shard, 1 replica/shard |
| us-west-2 | engine/encryption params null (Global Datastore 상속) |
| Go Client | `go-redis ClusterClient + TLS` (NewClusterClient 필수) |
| 용도 | Cart 서비스 (세션, 장바구니) |

:::caution ElastiCache Secondary 제약
Secondary에서는 `engine`, `engine_version`, encryption 파라미터를 **null**로 설정해야 합니다 (Global Datastore에서 상속). `automatic_failover_enabled`는 lifecycle `ignore_changes`에 추가.
:::

## Amazon MSK

| 속성 | 값 |
|------|-----|
| Instance | `kafka.m5.large` |
| Brokers | 3 per region |
| 인증 | SASL/SCRAM (port 9096) |
| EBS | 100 GiB per broker |
| Cross-region | **Independent** (Replicator 미설정) |

## OpenSearch

| 속성 | 값 |
|------|-----|
| Domain | `production-os-use1` / `production-os-usw2` (28자 제한) |
| Master | 3× `r6g.medium.search` |
| Data | 3× `r6g.medium.search` |
| EBS | 100 GiB per node |
| Cross-region | Independent |

:::tip Domain Name 제약
OpenSearch 도메인 이름은 **28자 제한**입니다. 리전 코드를 `use1`, `usw2`로 축약합니다.
:::

## S3

리전별 두 개의 S3 버킷:

- **Static Assets**: `production-mall-static-assets-{region}` — 프론트엔드 정적 파일, CloudFront OAC로 배포
- **Analytics**: `production-mall-analytics-{region}` — 분석 데이터 저장

S3 KMS 정책에 CloudFront 서비스 프린시펄의 `kms:Decrypt` 권한 추가 (OAC 복호화용).

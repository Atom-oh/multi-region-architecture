---
sidebar_position: 7
title: Data Strategy
description: AZ-Local 데이터 접근 — Aurora, DocumentDB, ElastiCache, MSK, OpenSearch
---

# Data Strategy

## 핵심 원칙

데이터 스토어는 공유 VPC에 배포하되, 각 EKS 클러스터는 같은 AZ의 데이터 노드에 우선 접근합니다. **쓰기는 항상 Writer(또는 Primary)로, 읽기만 AZ-local로 라우팅**합니다.

## Aurora PostgreSQL

| 속성 | 값 |
|------|-----|
| Engine | Aurora PostgreSQL `17.7` |
| Cluster | `is_primary=true` (독립 클러스터, Global Cluster 미참여) |
| Topology | Writer 1 (AZ-A) + **Reader 2** (AZ-A, AZ-C 각 1개) |
| Custom Endpoints | `reader-az-a`, `reader-az-c` |
| 환경변수 | `DB_WRITE_HOST` (Writer) + `DB_READ_HOST_LOCAL` (AZ Custom EP) |

```
              ┌─────────────────────┐
              │   Writer (AZ-A)     │
              │ Writes from both AZs│
              └─────┬─────┬─────────┘
                    │     │
          replication     replication
                    │     │
         ┌──────────▼┐   ┌▼──────────┐
         │Reader AZ-A │   │Reader AZ-C │
         │Custom EP:  │   │Custom EP:  │
         │reader-az-a │   │reader-az-c │
         └────────────┘   └────────────┘
```

:::info Custom Endpoint
Aurora Custom Endpoint는 특정 AZ의 reader만 포함하도록 구성됩니다. EKS AZ-A 클러스터는 `reader-az-a` 엔드포인트를 사용하여 AZ-A의 reader에만 접근하고, AZ-C 클러스터는 `reader-az-c`를 사용합니다.
:::

### Terraform Configuration

```hcl
module "aurora" {
  is_primary                = true        # 독립 클러스터
  global_cluster_identifier = ""          # Global 미참여
  reader_count              = 2
  reader_availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]
  # Aurora module creates Custom Endpoints per AZ
}
```

## DocumentDB

:::warning Custom Endpoint 미지원
DocumentDB는 Aurora와 달리 **Custom Endpoint를 지원하지 않습니다**. 따라서 **개별 Instance Endpoint**를 직접 환경변수로 주입하는 방식을 사용합니다.
:::

| 속성 | 값 |
|------|-----|
| Cluster | Global Cluster secondary (`is_primary=false`) |
| Instances | 2 (db.r6g.large) |
| Source | us-east-1 (Global primary) |
| AZ-local | 개별 Instance Endpoint per AZ |

| 환경변수 | AZ-A | AZ-C |
|----------|------|------|
| `DOCUMENTDB_HOST` | AZ-A instance endpoint | AZ-C instance endpoint |

### Terraform Configuration

```hcl
module "documentdb" {
  is_primary                = false
  global_cluster_identifier = "multi-region-mall-docdb"
  source_region             = "us-east-1"
  instance_count            = 2
  instance_class            = "db.r6g.large"
}
```

## ElastiCache (Valkey)

| 속성 | 값 |
|------|-----|
| Type | **Standalone** (Global Datastore 미참여) |
| Instance | `cache.r6g.large`, 1 shard, 1 replica |
| AZ-local | Go: `RouteByLatency: true`, Python: `read_from_replicas=True`, Java: `ReadFrom.NEAREST` |
| 환경변수 | `PREFER_REPLICA_AZ=ap-northeast-2a` (or 2c) |

:::tip 왜 Standalone?
한국 리전은 독립 운영 단위입니다. US Global Datastore에 참여하면 cross-region 레이턴시가 추가되므로, 독립 클러스터가 적합합니다.
:::

### AZ-Local Read Pattern

```
ElastiCache Cluster (Shared)
├── Primary Node (AZ-A)
│   ← EKS AZ-A: RouteByLatency → 자연스럽게 Primary 선호
└── Replica Node (AZ-C)
    ← EKS AZ-C: RouteByLatency → 자연스럽게 Replica 선호
```

## MSK (Kafka)

| 속성 | 값 |
|------|-----|
| Brokers | **4** (2 in AZ-A + 2 in AZ-C) |
| Instance | `kafka.m5.large` |
| AZ-local 소비 | `client.rack` (Java), `KAFKA_BROKERS_LOCAL` (Go/Python) |
| rack-aware | Go: `RackAffinityGroupBalancer`, Java: `client.rack` |

:::info 4 Brokers
MSK의 `number_of_broker_nodes`는 AZ 수의 배수여야 합니다. 2 AZ에서 최소 2지만, HA와 처리량을 위해 **4 (2+2)**를 선택. Codex의 `KAFKA_BROKERS_LOCAL` 패턴으로 rack-aware가 안 되는 Go/Python에서도 AZ locality를 확보합니다.
:::

### rack-aware Consumer Pattern

```
MSK Cluster (4 Brokers)
├── Broker-1 (AZ-A) ← EKS AZ-A: client.rack=ap-northeast-2a → 로컬 소비
├── Broker-2 (AZ-A) ← EKS AZ-A: KAFKA_BROKERS_LOCAL 사용
├── Broker-3 (AZ-C) ← EKS AZ-C: client.rack=ap-northeast-2c → 로컬 소비
└── Broker-4 (AZ-C) ← EKS AZ-C: KAFKA_BROKERS_LOCAL 사용
```

## OpenSearch

| 속성 | 값 |
|------|-----|
| Domain | 독립 도메인 (리전별) |
| Master | 3x `r6g.large.search` |
| Data | 2x `r6g.large.search` (2-AZ) |
| AZ Count | `availability_zone_count = 2` |

OpenSearch는 내부적으로 AZ-aware shard allocation을 수행합니다. `zone_awareness_enabled = true`로 데이터 노드가 AZ별로 분산됩니다.

## Data Store Comparison (US vs Korea)

| Data Store | US (Multi-Region) | Korea (Multi-AZ) |
|------------|-------------------|-------------------|
| **Aurora** | Global Cluster (Write Forwarding) | 독립 클러스터 + Custom EP per AZ |
| **DocumentDB** | Global Cluster (Primary/Secondary) | Global Secondary + Instance EP per AZ |
| **ElastiCache** | Global Datastore | Standalone (독립) |
| **MSK** | Independent per region | Independent, 4 brokers (2+2) |
| **OpenSearch** | Independent per region | Independent, 2-AZ |
| **S3** | Cross-region replication | Secondary (no replication) |

---
sidebar_position: 8
title: Microservices
description: 20개 마이크로서비스 — 5개 도메인, 3가지 기술 스택
---

# Microservices

## Domain Decomposition

### Core Domain

| Service | Stack | Data Store |
|---------|-------|------------|
| product-catalog | Python/FastAPI | DocumentDB |
| inventory | Go/Gin | Aurora DSQL |
| cart | Go/Gin | ElastiCache (Valkey) |
| search | Python/FastAPI | OpenSearch |

### User Domain

| Service | Stack | Data Store |
|---------|-------|------------|
| user-account | Java/Spring Boot | Aurora |
| user-profile | Python/FastAPI | DocumentDB |
| review | Python/FastAPI | DocumentDB |
| wishlist | Python/FastAPI | DocumentDB |

### Fulfillment Domain

| Service | Stack | Data Store |
|---------|-------|------------|
| order | Java/Spring Boot | Aurora |
| payment | Java/Spring Boot | Aurora |
| shipping | Go/Gin | Aurora DSQL |
| returns | Java/Spring Boot | Aurora |

### Business Domain

| Service | Stack | Data Store |
|---------|-------|------------|
| notification | Python/FastAPI | DocumentDB |
| recommendation | Python/FastAPI | DocumentDB |
| analytics | Python/FastAPI | ClickHouse / S3 |
| seller | Java/Spring Boot | Aurora |

### Platform Domain

| Service | Stack | Data Store |
|---------|-------|------------|
| api-gateway | Go/Gin | — |
| event-bus | Go/Gin | MSK (Kafka) |
| pricing | Java/Spring Boot | Aurora |
| warehouse | Java/Spring Boot | Aurora |

## Technology Stack Summary

| Stack | Count | 서비스 |
|-------|-------|--------|
| **Go / Gin** | 5 | api-gateway, event-bus, cart, inventory, shipping |
| **Python / FastAPI** | 8 | product-catalog, search, user-profile, review, wishlist, notification, recommendation, analytics |
| **Java / Spring Boot** | 7 | user-account, order, payment, returns, seller, pricing, warehouse |

## Container Configuration

| 설정 | 값 |
|------|-----|
| Image Registry | `123456789012.dkr.ecr.us-east-1.amazonaws.com/shopping-mall/*:latest` |
| Container Port | `8080` |
| K8s Service Port | `80 → targetPort: 8080` |
| Health Probes | `/health/ready`, `/health/live`, `/health/startup` |
| imagePullPolicy | `Always` (`:latest` 태그 노드 캐시 방지) |

## Inter-Service Communication

- **HTTP**: `mall_common/service_client.py` — httpx async로 서비스 간 HTTP 호출
- **Kafka**: event-bus 서비스를 통한 비동기 이벤트
- **K8s Service DNS**: `{service}.{namespace}.svc.cluster.local`

## K8s Namespaces

| Namespace | Services |
|-----------|----------|
| `core-services` | product-catalog, inventory, cart, search |
| `user-services` | user-account, user-profile, review, wishlist |
| `fulfillment-services` | order, payment, shipping, returns |
| `business-services` | notification, recommendation, analytics, seller |
| `platform` | api-gateway, event-bus, pricing, warehouse |

## Build & Deploy

```bash
# 전체 서비스 빌드
scripts/build-and-push.sh

# Go: context=src/
# Java: Maven build, context=src/
# Python: copies mall_common into service context
```

:::tip Python 공유 의존성
Python 서비스는 `mall_common` 패키지를 공유합니다. `mall_common/tracing.py`는 `redis` + `motor` 패키지를 requirements.txt에 포함해야 합니다.
:::

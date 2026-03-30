# Multi-Region Shopping Mall — Architecture Deep Research Report

**Date**: 2026-03-24

---

## Table of Contents

1. [Traffic Flow (End-to-End)](#1-traffic-flow-end-to-end)
2. [Infrastructure Layer (Terraform)](#2-infrastructure-layer-terraform)
   - 2.1 [Networking](#21-networking)
   - 2.2 [Data Stores](#22-data-stores)
   - 2.3 [Security](#23-security)
   - 2.4 [Compute (EKS)](#24-compute-eks)
3. [Kubernetes Layer](#3-kubernetes-layer)
   - 3.1 [Namespaces & Governance](#31-namespaces--governance)
   - 3.2 [Service Deployments](#32-service-deployments-20-services)
   - 3.3 [Region Overlays](#33-region-overlays)
   - 3.4 [ArgoCD (GitOps)](#34-argocd-gitops)
   - 3.5 [KEDA Event-Driven Autoscaling](#35-keda-event-driven-autoscaling)
4. [Microservice Architecture](#4-microservice-architecture)
   - 4.1 [Language Distribution](#41-language-distribution)
   - 4.2 [Shared Libraries](#42-shared-libraries)
   - 4.3 [Inter-Service Communication](#43-inter-service-communication)
   - 4.4 [Frontend](#44-frontend)
5. [Observability Stack](#5-observability-stack)
6. [Architecture Patterns & Decisions](#6-architecture-patterns--decisions)
7. [Gap Analysis & Resolution Strategies](#7-gap-analysis--resolution-strategies)
   - 7.1 [Gap 1: Authentication (P0)](#gap-1-authentication-p0-xl)
   - 7.2 [Gap 2: Event Bus → MSK (P0)](#gap-2-event-bus--msk-p0-l)
   - 7.3 [Gap 3: WAF 재활성화 (P1)](#gap-3-waf-재활성화-p1-m)
   - 7.4 [Gap 4: Search → OpenSearch (P1)](#gap-4-search--opensearch-p1-l)
   - 7.5 [Gap 5: DSQL Multi-Region (P1)](#gap-5-dsql-multi-region-p1-l)
   - 7.6 [Gap 6: MSK Replicator (P2)](#gap-6-msk-replicator-p2-m)
   - 7.7 [Gap 7: CI/CD (P2)](#gap-7-cicd-p2-l)
8. [DR/Failover 분석](#8-drfailover-분석)
9. [비용 분석 (월별 추정)](#9-비용-분석-월별-추정)
10. [성능/부하 테스트 전략](#10-성능부하-테스트-전략)

---

## Overview

AWS 멀티리전 쇼핑몰 플랫폼. **us-east-1** (Primary) + **us-west-2** (Secondary). 20개 마이크로서비스, 5개 도메인, Write-Primary/Read-Local 데이터 패턴.

---

## 1. Traffic Flow (End-to-End)

```
User → mall.atomai.click (Route53 ALIAS → CloudFront)
     → CloudFront (WAF: CommonRules, SQLi, BotControl, RateLimit 2000/IP, GeoBlock)
     ├── /static/* → S3 Static Assets (OAC auth)
     └── /api/*    → api-internal.atomai.click (Route53 Latency-Based)
                   → Nearest NLB (SG: CloudFront prefix list ONLY)
                   → api-gateway pods (EKS, reverse proxy)
                   → Backend microservice pods (K8s DNS discovery)
```

**Key Security**: ALB/NLB SGs restricted to `com.amazonaws.global.cloudfront.origin-facing` prefix list — **NO `0.0.0.0/0`**.

---

## 2. Infrastructure Layer (Terraform)

### 2.1 Networking

| Component | us-east-1 | us-west-2 |
|-----------|-----------|-----------|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Public Subnets | `10.0.1-3.0/24` (3 AZs) | `10.1.1-3.0/24` |
| Private Subnets | `10.0.11-13.0/24` | `10.1.11-13.0/24` |
| Data Subnets | `10.0.21-23.0/24` | `10.1.21-23.0/24` |
| NAT Gateways | 3 (per AZ) | 3 (per AZ) |
| Cross-Region | Transit Gateway Peering (ECMP, DNS enabled) |

**VPC Endpoints**: S3 (Gateway), ECR API/DKR, STS, CloudWatch Logs (Interface)

### 2.2 Data Stores

| Store | Engine | Topology | Replication | Use Case |
|-------|--------|----------|-------------|----------|
| **Aurora DSQL** | PostgreSQL-compatible (serverless) | Single-region (us-east-1) | N/A | Inventory, Shipping, Order, Payment, User-Account, Warehouse |
| **DocumentDB** | MongoDB 8.0 | Global Cluster (2 regions) | Async, write-forwarding | Product-Catalog, Recommendation, Review, Wishlist, Notification, Analytics, User-Profile |
| **ElastiCache** | Valkey 7.2 | Global Datastore (2 shards x 1 replica) | Active-Passive | Cart (session/cache) |
| **MSK** | Kafka (SASL/SCRAM) | Per-region (3 brokers) | Replicator (disabled) | Event-driven (planned) |
| **OpenSearch** | 2.17 | Per-region (3 master + 3 data) | None (app-level) | Search (planned) |
| **S3** | - | Cross-region replication | Active→Passive | Static assets, Analytics, Tempo traces |

**Kafka Topics** (12 pre-defined):
- `orders.created/confirmed/cancelled`, `payments.completed/failed`
- `catalog.updated/price-changed`, `inventory.reserved/released`
- `user.registered/activity`, `reviews.created`
- Config: `replication.factor=3`, `min.insync.replicas=2`, `retention=7d`

### 2.3 Security

| Layer | Implementation |
|-------|---------------|
| **KMS** | Per-service keys: aurora, documentdb, elasticache, msk, s3, opensearch (auto-rotation) |
| **Secrets Manager** | DocumentDB, MSK, OpenSearch creds (cross-region replicated, KMS encrypted) |
| **WAF** | AWS Managed Rules (Common, SQLi, BadInputs, BotControl) + Rate Limit + GeoBlock |
| **Network** | CloudFront-only ingress, prefix-list SGs, default-deny NetworkPolicies |
| **IAM/IRSA** | 20 service-specific roles + DSQL, Tempo, OTel, ALB controller roles |

### 2.4 Compute (EKS)

- **Cluster**: v1.35, private+public endpoint, KMS secrets encryption
- **Bootstrap Nodes**: t3.medium/t3a.medium (system workloads, taint: `node-role=system-critical:NoSchedule`)
- **Karpenter v1.9** — 6 NodePools:

| NodePool | Capacity | Instance Families | CPU Limit | Use Case |
|----------|----------|-------------------|-----------|----------|
| general | spot+on-demand | m6i/m7i, c6i/c7i, r6i/r7i | 200 | Default workloads |
| critical | **on-demand only** | m6i/m7i, r6i/r7i | 100 | api-gateway, order, payment, inventory |
| api-tier | on-demand | c6i/c7i (compute-opt) | 100 | API-focused workloads |
| worker-tier | spot+on-demand | m6i-m7a (multi-family) | 200 | Background workers |
| memory-tier | on-demand | r6i/r7i (memory-opt) | 100 | Cache-heavy services |
| batch-tier | **spot only** | m6i/c6i (multi-arch) | 300 | Batch processing |

---

## 3. Kubernetes Layer

### 3.1 Namespaces & Governance

| Namespace | Services | CPU Req/Limit | Mem Req/Limit | Max Pods |
|-----------|----------|---------------|---------------|----------|
| core-services | product-catalog, search, cart, order, payment, inventory | 20/40 | 40/80Gi | 100 |
| user-services | user-account, user-profile, wishlist, review | 10/20 | 20/40Gi | 50 |
| fulfillment | shipping, warehouse, returns | 8/16 | 16/32Gi | 40 |
| business-services | pricing, recommendation, notification, seller | 12/24 | 24/48Gi | 60 |
| platform | api-gateway, event-bus, analytics | 15/30 | 30/60Gi | 80 |

**Network Policies**: Default-deny all → allow DNS → allow ALB→api-gateway → allow inter-namespace (api-gateway→all, core→business/user, intra-namespace)

### 3.2 Service Deployments (20 services)

| Service | Lang | Replicas | CPU | Memory | HPA | Node Pool | Database |
|---------|------|----------|-----|--------|-----|-----------|----------|
| api-gateway | Go | 3 | 500m/1 | 1Gi/2Gi | 3-20 | critical | — |
| product-catalog | Python | 3 | 250m/500m | 512Mi/1Gi | 3-10 | general | DocumentDB+Valkey |
| search | Go | 3 | 500m/1 | 1Gi/2Gi | 3-15 | general | (OpenSearch planned) |
| cart | Go | 3 | 250m/500m | 512Mi/1Gi | 3-20 | general | Valkey |
| order | Java | 3 | 500m/1 | 1Gi/2Gi | 3-10 | critical | Aurora DSQL |
| payment | Java | 3 | 500m/1 | 1Gi/2Gi | 3-10 | critical | Aurora DSQL |
| inventory | Go | 3 | 500m/1 | 1Gi/2Gi | 3-15 | critical | Aurora DSQL |
| user-account | Java | 3 | 250m/500m | 512Mi/1Gi | 3-10 | critical | Aurora DSQL |
| user-profile | Python | 2 | 250m/500m | 512Mi/1Gi | 2-8 | general | DocumentDB |
| wishlist | Python | 2 | 125m/250m | 256Mi/512Mi | 2-6 | general | DocumentDB+Valkey |
| review | Python | 2 | 250m/500m | 512Mi/1Gi | 2-8 | general | DocumentDB |
| shipping | Python | 2 | 250m/500m | 512Mi/1Gi | 2-8 | general | Aurora DSQL |
| warehouse | Java | 2 | 250m/500m | 512Mi/1Gi | 2-6 | general | Aurora DSQL |
| returns | Java | 2 | 250m/500m | 512Mi/1Gi | 2-6 | general | — |
| pricing | Java | 2 | 250m/500m | 512Mi/1Gi | 2-8 | general | — (mock) |
| recommendation | Python | 2 | 500m/1 | 1Gi/2Gi | 2-10 | general | DocumentDB+Valkey |
| notification | Python | 2 | 125m/250m | 256Mi/512Mi | 2-6 | general | DocumentDB |
| seller | Java | 2 | 250m/500m | 512Mi/1Gi | 2-6 | general | — (mock) |
| event-bus | Go | 3 | 500m/1 | 1Gi/2Gi | 3-10 | critical | — (MSK planned) |
| analytics | Python | 2 | 500m/1 | 1Gi/2Gi | 2-8 | general | DocumentDB |

**Common**: port 8080, probes `/health/{ready,live,startup}`, `imagePullPolicy: Always`, TopologySpreadConstraints (maxSkew=1 across AZs)

### 3.3 Region Overlays

Kustomize overlays inject region-specific configs via ConfigMapGenerator (`region-config`):
- DocumentDB, Valkey, MSK, OpenSearch endpoints
- `REGION_ROLE=PRIMARY|SECONDARY`, `AWS_REGION`
- `OTEL_EXPORTER_OTLP_ENDPOINT`
- TargetGroupBinding ARNs, NLB SG IDs, ACM cert ARNs

### 3.4 ArgoCD (GitOps)

**18 ApplicationSets** via app-of-apps pattern:
- 5 domain AppSets (core, user, fulfillment, business, platform)
- 6 Helm AppSets (Karpenter, Prometheus, External-Secrets, FluentBit, OTel, ALB Controller)
- 7 infra AppSets (Tempo, StorageClass, Grafana NLB, etc.)
- Sync: automated prune + selfHeal, retry 5x exponential backoff

### 3.5 KEDA Event-Driven Autoscaling

| Service | Kafka Topic | Lag Threshold | Min/Max |
|---------|-------------|---------------|---------|
| order | orders | 100 | 2/20 |
| payment | payments | 50 | 2/15 |
| inventory | inventory | 200 | 2/12 |
| search | products | 500 | 2/10 |
| shipping | orders | 100 | 2/15 |
| warehouse | orders | 150 | 2/10 |
| returns | returns | 100 | 1/8 |

---

## 4. Microservice Architecture

### 4.1 Language Distribution

| Language | Framework | Count | Services |
|----------|-----------|-------|----------|
| Go 1.24 | Gin | 5 | api-gateway, cart, inventory, search, event-bus |
| Python 3.12 | FastAPI | 8 | product-catalog, recommendation, review, wishlist, notification, analytics, user-profile, shipping |
| Java 21 | Spring Boot | 7 | order, payment, pricing, user-account, returns, warehouse, seller |

### 4.2 Shared Libraries

**Go** (`src/shared/go/pkg/`): config, tracing (OTel+Gin+HTTP), aurora (pgxpool+IAM), valkey (cluster+TLS), kafka (producer/consumer), health

**Python** (`src/shared/python/mall_common/`): config (Pydantic), documentdb (Motor async), tracing (OTel+FastAPI+httpx+pymongo+redis), valkey (async), service_client (httpx 2s timeout), kafka, health

**Java**: No shared library — each service standalone. `DataSourceAutoConfiguration` excluded, mock fallback. OTel Java agent auto-instrumentation.

### 4.3 Inter-Service Communication

**Pattern**: DNS-based discovery (no service mesh)
```
http://{service}.{namespace}.svc.cluster.local:80
```

| Caller | Callee | Purpose |
|--------|--------|---------|
| api-gateway | All 17 backends | Reverse proxy routing |
| cart | product-catalog | Fetch product details |
| search | product-catalog | Index products |
| order | inventory, payment, shipping | Order workflow (parallel calls) |
| returns | order | Fetch order for return |

### 4.4 Frontend

**Stack**: React 18 + Vite + React Router + TailwindCSS
**Pages**: 12 (Home, Products, ProductDetail, Cart, Checkout, Orders, OrderDetail, Profile, Wishlist, Notifications, SellerDashboard, Returns)
**API**: `/api/v1` via api-gateway proxy, `mapProduct()`/`mapOrder()` normalizers

---

## 5. Observability Stack

| Component | Version | Mode | Backend |
|-----------|---------|------|---------|
| OTel Collector | ADOT 0.40.0 | DaemonSet | → Tempo + X-Ray + Prometheus |
| Tempo | 2.6.1 | Monolithic | S3 (30d→IA, 90d→Glacier, 365d→Delete) |
| Prometheus | kube-prometheus-stack 68.4.0 | 2 replicas, 50Gi | gp3 PVC |
| Grafana | Helm | 2 replicas, 10Gi | Datasources: Prometheus, Tempo, CloudWatch (both regions) |
| FluentBit | DaemonSet | → CloudWatch | `/eks/{cluster}/containers` |
| X-Ray | Sampling rules | — | Errors=100%, Orders=100%, Default=5% |

**OTel Sampling**: Tail-based — errors=100%, slow>500ms=100%, default=10%

---

## 6. Architecture Patterns & Decisions

| Decision | Rationale |
|----------|-----------|
| **Write-Primary/Read-Local** | Aurora/DocumentDB global clusters — writes to us-east-1, reads local. Minimizes write latency while keeping reads fast. |
| **Transit Gateway (not VPC Peering)** | Better scalability, routing control, supports future region additions |
| **CloudFront-only ingress** | Zero direct ALB/NLB exposure. Prefix-list SGs ensure enforcement at network level |
| **IRSA everywhere** | Fine-grained per-service IAM. IMDS restricted in EKS 1.35 |
| **Karpenter 6-pool design** | Workload isolation: critical (on-demand), batch (spot-only), general (mixed) |
| **DNS discovery (no mesh)** | Simplicity. NetworkPolicies handle segmentation. OTel handles observability |
| **KEDA + HPA dual scaling** | HPA for CPU/memory, KEDA for event-driven (Kafka lag) |
| **App-of-apps ArgoCD** | Single root-app manages 18 AppSets. Automated sync + self-heal |
| **Per-service KMS keys** | Granular access control and audit per data store type |
| **3-tier subnet design** | Public (NAT/IGW), Private (EKS nodes), Data (RDS/DocDB/ElastiCache) |

---

## 7. Gap Analysis & Resolution Strategies

### 우선순위 실행 순서

| # | Gap | Priority | Complexity | Dependencies | Rationale |
|---|-----|----------|------------|--------------|-----------|
| 1 | Authentication (Cognito) | **P0** | XL | None | 보안 최우선, 모든 API 무인증 상태 |
| 2 | Event Bus → MSK | **P0** | L | None | 이벤트 기반 아키텍처 기반, Gap 1/3 선행 |
| 3 | WAF 재활성화 | **P1** | M | None | 보안, Count 모드로 시작 가능 |
| 4 | Search → OpenSearch | **P1** | L | Gap 2 | 사용자 대면, Kafka 인덱싱 필요 |
| 5 | DSQL Multi-Region | **P1** | L | None | 데이터 일관성, write-forwarding부터 시작 |
| 6 | MSK Replicator 활성화 | **P2** | M | Gap 2 | 크로스리전 이벤트 일관성 |
| 7 | CI/CD 자동화 | **P2** | L | None | 개발 속도, 기능 차단 아님 |

### Gap 1: Authentication (P0, XL)
- **현재**: `user-account/Controller.java:103-149` — mock JWT 반환, api-gateway에 auth middleware 없음
- **방안**: Cognito User Pool (us-east-1) + JWT validation middleware
- **파일**:
  - Create: `terraform/modules/security/cognito/main.tf` (User Pool, App Client)
  - Create: `src/shared/go/pkg/auth/middleware.go` (JWT validation)
  - Modify: `src/services/api-gateway/main.go` (protected routes에 middleware 추가)
- **리스크**: 높음 — feature flag + shadow mode 우선 적용 권장

### Gap 2: Event Bus → MSK (P0, L)
- **현재**: `event-bus/main.go:97-121` — mock topic list, 실제 publish 없음
- **기존 자산**: Go/Python Kafka 라이브러리 존재, consumer 파일도 이미 작성됨 (notification, analytics, recommendation, shipping)
- **방안**: event-bus에 실제 MSK producer 연결 → 7개 consumer 서비스 활성화
- **파일**: Modify `event-bus/main.go`, `order/Controller.java`, `inventory/main.go` 등 10+ 서비스
- **KEDA**: ScaledObject 이미 구성됨, MSK endpoint만 주입하면 동작

### Gap 3: WAF 재활성화 (P1, M)
- **현재**: Bot Control이 curl/headless 차단하여 비활성화
- **방안**: scope-down rule로 Bot Control 튜닝 → Count 모드 2주 → Block 전환
- **파일**: Modify `terraform/modules/edge/waf/main.tf:81-101`, Create IP allowlist

### Gap 4: Search → OpenSearch (P1, L)
- **현재**: `search/main.go:46-57` — `strings.Contains()` mock 필터링
- **방안**: OpenSearch Go client 패키지 생성 → Kafka 이벤트로 인덱싱 파이프라인 구축
- **리전 동기화**: 각 리전 독립 OpenSearch → Kafka 이벤트 기반 양쪽 인덱싱

### Gap 5: DSQL Multi-Region (P1, L)
- **현재**: us-east-1만 DSQL, us-west-2는 mock fallback
- **Option A** (권장): DSQL Linked Clusters (`linked_cluster_arns`)
- **Option B**: Write-forwarding (us-west-2 쓰기 → Transit GW → us-east-1)
- **영향**: 6개 서비스 (inventory, shipping, order, payment, user-account, warehouse)

### Gap 6: MSK Replicator (P2, M)
- **현재**: `enable_replicator = false` (IAM Auth 필요)
- **방안**: MSK에 IAM Auth 추가 (SASL/SCRAM 병행) → replicator 활성화
- **파일**: Modify `terraform/environments/production/*/main.tf`

### Gap 7: CI/CD (P2, L)
- **현재**: 수동 `scripts/build-and-push.sh`, GitHub Actions workflow 주석 처리됨
- **방안**: 기존 워크플로우 재활성화 + per-service path filtering + ArgoCD Rollouts canary
- **파이프라인**: PR→lint/test→merge→integration→deploy us-east-1 (canary 10%)→smoke→100%→us-west-2

---

## 8. DR/Failover 분석

### 현재 RTO/RPO 매트릭스

| Component | RTO (현재) | RPO (현재) | 자동화 수준 | 위험도 |
|-----------|-----------|-----------|------------|--------|
| **Traffic Routing** | 1-2분 | 0 | **자동** (Route53 health check 10s x 3) | 낮음 |
| **Aurora DSQL** | **N/A (DR 없음)** | **전체 손실** | 없음 | **치명적** |
| **DocumentDB** | 5-15분 | <1분 | **수동** (CLI failover) | 높음 |
| **ElastiCache** | 1-5분 | <1초 | **수동** (CLI promotion) | 중간 |
| **MSK** | **N/A (DR 없음)** | **전체 손실** | 없음 | **치명적** |
| **OpenSearch** | **수시간 (재구축)** | **전체 손실** | 없음 | **높음** |
| **S3** | 즉시 | <15분 | **자동** (CRR) | 낮음 |
| **EKS Workloads** | 2-5분 | 0 | **자동** (Karpenter) | 낮음 |

### 시나리오 1: us-east-1 완전 장애

**자동 처리되는 것:**
- Route53 health check → 30초 감지 → us-west-2로 트래픽 전환
- S3 cross-region replica에서 정적 자산 서빙

**수동 개입 필요:**
1. DocumentDB secondary 승격: `aws docdb failover-global-cluster --target-db-cluster-identifier production-docdb-global-us-west-2`
2. ElastiCache secondary 승격: `aws elasticache failover-global-replication-group --primary-region us-west-2`
3. DSQL 데이터 **손실 수용** — 서비스 mock 모드로 전환
4. MSK 이벤트 **손실 수용** — 토픽 수동 재생성

### 시나리오 2: EKS 클러스터 장애
- Karpenter가 노드 교체 시도 (2-5분)
- ArgoCD가 실패 워크로드 자동 재배포
- **Gap**: PodDisruptionBudget 미정의 — 업그레이드 시 서비스 중단 가능

### 시나리오 3: 개별 데이터 스토어 장애
- **DSQL 장애** → 6개 서비스 mock 모드 (graceful degradation 구현됨)
- **DocumentDB 장애** → 수동 글로벌 failover, 5-15분 RTO
- **Valkey 장애** → 수동 promotion, cart 데이터 일시 유실 가능

### DR 개선 우선순위

| # | 개선 사항 | 노력 | 영향 |
|---|----------|------|------|
| 1 | **DSQL Linked Clusters 구성** | M | DSQL 단일 리전 위험 제거 |
| 2 | **MSK Replicator 활성화** | M | 크로스리전 이벤트 복제 |
| 3 | **데이터 스토어 failover 자동화** (Lambda + EventBridge) | H | RTO 15분→2분 단축 |
| 4 | **PDB 추가** (모든 서비스) | L | 유지보수 시 서비스 안정성 |
| 5 | **Route53 health check 경로 수정** (`/` → `/health/ready`) | L | 정확한 헬스 감지 |
| 6 | **CloudFront Origin Failover Group** | M | Route53 장애 대비 |

### DR Drill 전략
- **분기별**: 전체 us-east-1 장애 시뮬레이션 (Route53 health check 비활성화)
- **월별**: 개별 데이터 스토어 failover 테스트 (DocumentDB, ElastiCache)
- **주간**: `scripts/test-traffic-flow.sh --region both` + replication lag 확인
- **도구**: AWS Fault Injection Simulator (FIS)로 네트워크 지연/AZ 장애 주입

---

## 9. 비용 분석 (월별 추정)

### 인프라 비용 (per region, 2개 리전 합산)

| Category | Service | Spec | 월비용 (추정) |
|----------|---------|------|--------------|
| **Compute** | EKS Control Plane | 2 clusters | $146 |
| | EC2 (Karpenter) | ~14 nodes x m6i.large (mixed spot/OD) | $2,800-4,200 |
| | EC2 (Bootstrap) | 4x t3.medium | $240 |
| **Database** | Aurora DSQL | Serverless (pay-per-use) | $200-500 |
| | DocumentDB | 4x db.r6g.large (2 per region) | $1,480 |
| | ElastiCache | 4x cache.r7g.medium (2 shards x 2 regions) | $880 |
| | OpenSearch | 12x r6g.medium (3 master + 3 data x 2) | $1,560 |
| **Messaging** | MSK | 6x kafka.m5.large (3 per region) | $1,620 |
| **Networking** | NAT Gateway | 6 (3 per region) | $270 + data transfer |
| | Transit Gateway | 2 TGW + peering | $146 + data transfer |
| | NLB | 2 | $36 + LCU |
| **Edge** | CloudFront | 1 distribution | $50-500 (트래픽 비례) |
| | WAF | 1 Web ACL (현재 비활성) | $0 (비활성) |
| **Storage** | S3 | Static + Analytics + Tempo | $50-200 |
| **Observability** | CloudWatch Logs | 5 log groups per region | $100-300 |
| | X-Ray | Trace storage | $50-100 |
| **Security** | KMS | 12 keys (6 per region) | $24 |
| | Secrets Manager | 6 secrets (replicated) | $5 |
| **합계** | | | **$9,600-12,400/월** |

### 비용 최적화 기회

| 기회 | 절감 추정 | 난이도 |
|------|----------|--------|
| **Karpenter Spot 비율 확대** (현재 general pool만 spot) | 30-40% EC2 절감 | 낮음 |
| **DocumentDB → 소규모 인스턴스** (r6g.large → r6g.medium, 트래픽 낮은 경우) | $370/월 | 낮음 |
| **MSK Serverless 전환** (현재 provisioned) | 50-70% MSK 절감 (저트래픽 시) | 중간 |
| **OpenSearch 스케일 다운** (dedicated master 제거, 저트래픽 시) | $520/월 | 낮음 |
| **NAT Gateway → NAT Instance** (비용 민감 시) | $200/월 | 중간 |
| **Reserved Instances** (DocumentDB, ElastiCache 1년) | 30-40% | 낮음 |
| **S3 Intelligent-Tiering** | $20-50/월 | 낮음 |

---

## 10. 성능/부하 테스트 전략

### 10.1 발견된 병목 (Critical Bugs)

| # | 병목 | 위치 | 영향 | 우선순위 |
|---|------|------|------|----------|
| 1 | **Python Valkey 클라이언트 오류** | `mall_common/valkey.py:11-15` | `Redis()` 사용 → Cluster에서 MOVED 에러 | **P0 버그** |
| 2 | **DSQL 커넥션 풀 미설정** | `shared/go/pkg/aurora/client.go:35-53` | pgxpool 기본값 (4 conn/CPU) → 부하 시 고갈 | **P0** |
| 3 | **DocumentDB 커넥션 풀 미설정** | `mall_common/documentdb.py:9-13` | Motor 기본값 (100/pod) → r6g.large 1000 limit 초과 가능 | **P0** |
| 4 | **API Gateway HTTP 풀 미설정** | `api-gateway/main.go:92-132` | `MaxIdleConnsPerHost=2` (기본값) → upstream 병목 | **P1** |
| 5 | **Java HTTP 클라이언트 풀 없음** | `order/Controller.java:22-26` | `SimpleClientHttpRequestFactory` → 요청당 새 연결 | **P1** |

### 10.2 부하 테스트 도구: **k6** (권장)

| 도구 | 장점 | 단점 | 적합도 |
|------|------|------|--------|
| **k6** | K8s operator 네이티브, Prometheus 연동, JS | Java 네이티브 아님 | **최적** |
| Locust | Python 친화적, 분산 | K8s 연동 약함 | 대안 |
| Gatling | Java 최적, 상세 리포트 | Scala DSL 학습곡선 | Java only |

### 10.3 테스트 시나리오

| 시나리오 | 트래픽 비중 | 경로 | 목표 p95 |
|----------|-----------|------|----------|
| **Browse Flow** | 60% | Home → 상품목록 → 상품상세 | <200ms |
| **Purchase Flow** | 15% | 장바구니 → 결제 → 주문 → 배송 | <500ms (primary), <800ms (secondary) |
| **Search Flow** | 20% | 검색 → 필터 → 정렬 → 페이지네이션 | <300ms |
| **Seller Flow** | 5% | 대시보드 → 상품관리 → 분석 → 재고수정 | <400ms |

### 10.4 부하 프로파일

| Profile | VUs | 시간 | 목적 |
|---------|-----|------|------|
| Baseline | 100 | 10분 | 기준 메트릭 수집 |
| Ramp-up | 100→1000 | 30분 | HPA/Karpenter 스케일링 트리거 검증 |
| Steady-state | 500 | 60분 | 안정성 검증 |
| Spike | 500→2000→500 | 15분 | 급격한 트래픽 증가 대응 |
| Soak | 300 | 4시간 | 메모리 누수, 커넥션 고갈 감지 |

### 10.5 목표 메트릭

| Metric | Target | Alert |
|--------|--------|-------|
| p50 latency | <100ms | >150ms |
| p95 latency | <300ms | >500ms |
| p99 latency | <500ms | >1000ms |
| Throughput | 5,000 RPS | <4,000 RPS |
| Error rate | <0.1% | >1% |

### 10.6 성능 최적화 권장사항

| # | 최적화 | 대상 파일 | 영향 |
|---|--------|----------|------|
| 1 | Python Valkey → `RedisCluster` 수정 | `mall_common/valkey.py` | MOVED 에러 해소 |
| 2 | DSQL pool 명시 설정 (MaxConns=25, MinConns=5) | `shared/go/pkg/aurora/client.go` | 커넥션 고갈 방지 |
| 3 | DocumentDB pool 제한 (maxPoolSize=50) | `mall_common/documentdb.py` | DB 커넥션 limit 보호 |
| 4 | API GW transport 설정 (MaxIdleConnsPerHost=50) | `api-gateway/main.go` | upstream 병목 해소 |
| 5 | Java → `HttpComponentsClientHttpRequestFactory` | `order/Controller.java` 등 | 커넥션 재사용 |
| 6 | 상품목록 Valkey 캐싱 추가 (5min TTL) | product-catalog | DocumentDB 부하 감소 |
| 7 | CloudFront 읽기 API 캐싱 (products 5min) | `terraform/modules/edge/cloudfront/` | origin 부하 감소 |

### 10.7 부하 테스트 중 모니터링

**Grafana 대시보드:**
- API Gateway: endpoint별 RPS, p50/p95/p99, 에러율
- DB Connections: DSQL active connections, DocumentDB pool utilization
- K8s Resources: HPA replica count, Karpenter node count by pool, CPU/Mem
- KEDA: Kafka consumer lag, ScaledObject replica count

**Prometheus 알림:**
```
HighP95Latency: histogram_quantile(0.95, ...) > 0.5 for 5m
HighErrorRate: rate(5xx) / rate(total) > 0.01 for 2m
DBPoolExhausted: acquired/max > 0.9 for 1m
HPAAtMax: current == max for 10m
```

**Tempo 쿼리:**
```
{ resource.service.name="order" } | duration > 500ms
{ span.attributes.db.system="postgresql" } | duration > 100ms
```

---

*This report was generated from deep architecture research conducted on 2026-03-24.*

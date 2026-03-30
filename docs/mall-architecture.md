# Shopping Mall Application Architecture

Multi-region shopping mall platform: 20 microservices across 5 domains, deployed on EKS in us-east-1 (primary) and us-west-2 (secondary).

## Traffic Flow

```mermaid
graph TD
    User([User]) -->|HTTPS| DNS[mall.atomai.click<br/>Route53]
    DNS --> CF[CloudFront + WAF]
    CF -->|Latency-based routing| NLB_E[NLB us-east-1]
    CF -->|Latency-based routing| NLB_W[NLB us-west-2]
    NLB_E --> AG_E[api-gateway<br/>us-east-1]
    NLB_W --> AG_W[api-gateway<br/>us-west-2]

    AG_E --> SVC_E[20 Microservices]
    AG_W --> SVC_W[20 Microservices]

    style User fill:#ff9800
    style CF fill:#2196f3
    style DNS fill:#9c27b0
    style NLB_E fill:#4caf50
    style NLB_W fill:#4caf50
    style AG_E fill:#009688
    style AG_W fill:#009688
```

## Domain Architecture

### 5 Domains, 20 Services

```mermaid
graph LR
    subgraph Core["Core Services (core-services ns)"]
        PC[product-catalog<br/>Python/FastAPI]
        INV[inventory<br/>Go/Gin]
        PRC[pricing<br/>Python/FastAPI]
        SR[search<br/>Go/Gin]
        CT[cart<br/>Go/Gin]
        ORD[order<br/>Java/Spring]
        PAY[payment<br/>Java/Spring]
    end

    subgraph User["User Services (user ns)"]
        UA[user-account<br/>Java/Spring]
        UP[user-profile<br/>Python/FastAPI]
        WL[wishlist<br/>Python/FastAPI]
        RV[review<br/>Python/FastAPI]
    end

    subgraph Fulfillment["Fulfillment (fulfillment ns)"]
        SH[shipping<br/>Java/Spring]
        WH[warehouse<br/>Java/Spring]
        RT[returns<br/>Python/FastAPI]
    end

    subgraph Business["Business (business ns)"]
        PRM[pricing<br/>Python/FastAPI]
        REC[recommendation<br/>Python/FastAPI]
        NF[notification<br/>Java/Spring]
        SEL[seller<br/>Python/FastAPI]
    end

    subgraph Platform["Platform (platform ns)"]
        AG[api-gateway<br/>Go/Gin]
        EB[event-bus<br/>Python/FastAPI]
        AN[analytics<br/>Python/FastAPI]
        SM[synthetic-monitor<br/>Python CronJob]
    end
```

## Inter-Service Communication (Distributed Tracing)

Services make internal HTTP calls with W3C Trace Context propagation (`traceparent`/`tracestate` headers). The OTel Collector captures and exports traces to Tempo.

### Cascading Call Chains

```mermaid
graph TD
    SM[Synthetic Monitor] -->|HTTPS| CF[CloudFront]
    CF -->|HTTP| AG[api-gateway]

    AG -->|/products| PC[product-catalog]
    AG -->|/search| SR[search]
    AG -->|/carts| CT[cart]
    AG -->|/orders| OR[order]
    AG -->|/payments| PM[payment]
    AG -->|/shipments| SH[shipping]
    AG -->|/inventory| IN[inventory]
    AG -->|/users| UA[user-account]
    AG -->|/profiles| UP[user-profile]
    AG -->|/notifications| NF[notification]
    AG -->|/recommendations| RC[recommendation]
    AG -->|/reviews| RV[review]
    AG -->|/sellers| SL[seller]
    AG -->|/warehouses| WH[warehouse]
    AG -->|/returns| RT[returns]
    AG -->|/wishlists| WL[wishlist]
    AG -->|/events| EB[event-bus]
    AG -->|/analytics| AN[analytics]
    AG -->|/prices| PR[pricing]

    OR ==>|재고 확인| IN
    OR ==>|결제 요청| PM
    OR ==>|배송 생성| SH
    CT ==>|상품 조회| PC
    SR ==>|결과 보강| PC

    SH -.->|Kafka| NF
    OR -.->|Kafka| AN
    PM -.->|Kafka| NF

    style SM fill:#ff9800
    style CF fill:#2196f3
    style AG fill:#4caf50
    style OR fill:#f44336
    style CT fill:#f44336
    style SR fill:#f44336
```

**Legend:**
- **Solid thick arrows (==>)**: Inter-service HTTP calls with trace propagation
- **Dashed arrows (-.->)**: Async Kafka events (planned)
- **Thin arrows (-->)**: API gateway routing

### Call Chain Details

| Source Service | Target Service | Endpoint | Purpose | Trace Propagation |
|---|---|---|---|---|
| **order** (Java) | inventory | `GET /api/v1/inventory/{productId}` | 주문 시 재고 확인 | OTel Javaagent auto + manual traceparent |
| **order** (Java) | payment | `POST /api/v1/payments` | 결제 처리 요청 | OTel Javaagent auto + manual traceparent |
| **order** (Java) | shipping | `POST /api/v1/shipments` | 배송 생성 | OTel Javaagent auto + manual traceparent |
| **cart** (Go) | product-catalog | `GET /api/v1/products/{id}` | 장바구니 추가 시 상품 정보 조회 | OTel HTTP transport (otelhttp) |
| **search** (Go) | product-catalog | `GET /api/v1/products` | 검색 결과 보강 | OTel HTTP transport (otelhttp) |

### Expected Trace Waterfall (Tempo)

```
synthetic-monitor                    [=====================================]
  └─ CloudFront → api-gateway        [==================================]
       └─ POST /api/v1/orders (order)   [============================]
            ├─ GET /inventory/{id}         [========]  (inventory)
            ├─ POST /payments              [==========]  (payment)
            └─ POST /shipments             [========]  (shipping)

synthetic-monitor                    [=====================================]
  └─ CloudFront → api-gateway        [==================================]
       └─ POST /api/v1/carts (cart)     [========================]
            └─ GET /products/{id}          [========]  (product-catalog)

synthetic-monitor                    [=====================================]
  └─ CloudFront → api-gateway        [==================================]
       └─ GET /api/v1/search (search)   [========================]
            └─ GET /products               [========]  (product-catalog)
```

## Service Details

### Technology Stack

| Language | Framework | Services | OTel Instrumentation |
|---|---|---|---|
| **Go 1.22** | Gin | product-catalog(proxy), inventory, search, cart, api-gateway | `otelgin` middleware + `otelhttp` transport |
| **Java 21** | Spring Boot 3.2 | order, payment, shipping, user-account, warehouse, notification | OTel Javaagent v2.11.0 (auto-instrumentation) |
| **Python 3.13** | FastAPI | product-catalog, pricing, user-profile, wishlist, review, seller, returns, event-bus, analytics, recommendation | `opentelemetry-instrumentation-fastapi` |

### Service DNS (Cluster Internal)

All services are accessible via `<service-name>.<namespace>.svc.cluster.local:80`.

| Namespace | Services |
|---|---|
| `core-services` | product-catalog, inventory, pricing, search, cart, order, payment |
| `user` | user-account, user-profile, wishlist, review |
| `fulfillment` | shipping, warehouse, returns |
| `business` | pricing, recommendation, notification, seller |
| `platform` | api-gateway, event-bus, analytics, synthetic-monitor |

### Container Configuration

- **Image Registry**: `123456789012.dkr.ecr.us-east-1.amazonaws.com/shopping-mall/<service>:latest`
- **Container Port**: 8080
- **Service Port**: 80 → targetPort 8080
- **Health Probes**: `/health/ready`, `/health/live`, `/health/startup` (port 8080)
- **imagePullPolicy**: Always

## Data Architecture

```mermaid
graph TB
    subgraph Primary["us-east-1 (Primary - Write)"]
        AU_P[(Aurora PostgreSQL<br/>Writer)]
        DOC_P[(DocumentDB<br/>Primary)]
        EC_P[(ElastiCache Valkey<br/>Primary)]
        OS_P[(OpenSearch)]
        MSK_P[MSK Kafka]
    end

    subgraph Secondary["us-west-2 (Secondary - Read)"]
        AU_S[(Aurora PostgreSQL<br/>Reader + Write Forward)]
        DOC_S[(DocumentDB<br/>Secondary)]
        EC_S[(ElastiCache Valkey<br/>Replica)]
        OS_S[(OpenSearch)]
        MSK_S[MSK Kafka]
    end

    AU_P -.->|Global Cluster<br/>Replication| AU_S
    DOC_P -.->|Global Cluster<br/>Replication| DOC_S
    EC_P -.->|Global Datastore<br/>Replication| EC_S

    style Primary fill:#e3f2fd
    style Secondary fill:#fff3e0
```

**Data Pattern**: Write-Primary / Read-Local
- us-east-1 handles all writes
- us-west-2 reads locally, writes forwarded to primary via Aurora Global Write Forwarding

## Observability Stack

```mermaid
graph LR
    subgraph Services
        S1[Go Services]
        S2[Java Services]
        S3[Python Services]
    end

    subgraph Collection
        OC[OTel Collector<br/>DaemonSet]
        FB[FluentBit<br/>DaemonSet]
    end

    subgraph Storage
        T[Tempo<br/>S3 backend]
        P[Prometheus<br/>50Gi gp3]
        CW[CloudWatch<br/>Logs]
        XR[X-Ray]
    end

    subgraph Visualization
        G[Grafana]
    end

    S1 -->|OTLP gRPC| OC
    S2 -->|OTLP gRPC| OC
    S3 -->|OTLP gRPC| OC
    OC -->|Traces| T
    OC -->|Traces| XR
    OC -->|Metrics| P
    FB -->|Logs| CW
    T --> G
    P --> G

    style OC fill:#ff9800
    style G fill:#4caf50
```

- **Traces**: OTel Collector → Tempo (S3 backend) + X-Ray
- **Metrics**: OTel Collector → Prometheus (kube-prometheus-stack)
- **Logs**: FluentBit → CloudWatch Logs
- **Visualization**: Grafana (Tempo + Prometheus datasources)
- **Tail-based sampling**: errors=100%, slow>500ms=100%, default=10%

## EKS & Compute

- **Cluster**: `multi-region-mall` (EKS v1.35) in both regions
- **Bootstrap Nodes**: 2x m5.large (system workloads: Karpenter, ArgoCD, CoreDNS)
- **Application Nodes**: Karpenter v1.9 with 6 NodePools:
  - `general`: default workloads (c5, m5, r5)
  - `critical`: order, payment, shipping (c5, m5 on-demand)
  - `api-tier`: api-gateway, search (c5, m5)
  - `worker-tier`: event-bus, analytics (m5, r5 spot)
  - `batch-tier`: synthetic-monitor, batch jobs (m5 spot)
  - `memory-tier`: recommendation, cache-heavy (r5, r6i)

## Synthetic Monitor

CronJob (`*/2 * * * *`) running 7 E2E scenarios every 2 minutes in both regions:

| Scenario | Services Touched | Inter-Service Chains |
|---|---|---|
| S1: Browse & Search | product-catalog, search, pricing, review, recommendation | search → product-catalog |
| S2: User Registration | user-account, user-profile, notification | - |
| S3: Shopping Cart | product-catalog, inventory, cart, pricing, recommendation, wishlist | cart → product-catalog |
| S4: Purchase Flow | order, payment, shipping | order → inventory → payment → shipping |
| S5: Seller & Warehouse | seller, warehouse, inventory | - |
| S6: Post-Purchase | review, returns, notification | - |
| S7: Platform & Analytics | event-bus, analytics, recommendation | - |

### Grafana Dashboard

- **Stat panels**: Total traces, East/West breakdown, Error count
- **Scenario tables**: Per-scenario trace list with clickable Trace ID → Explore waterfall
- **Latency comparison**: East vs West timeseries
- **Heatmap**: Latency distribution
- **Trace Explorer**: Recent traces per region
- **Service Map**: Node graph showing service relationships

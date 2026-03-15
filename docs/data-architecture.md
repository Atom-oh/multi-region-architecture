# Data Architecture

## Polyglot Persistence Strategy

각 데이터 스토어는 워크로드 특성에 최적화된 용도로 사용됩니다.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Data Store Selection                         │
├──────────────────┬──────────────────┬───────────────────────────────┤
│   Workload Type  │   Data Store     │   Services                    │
├──────────────────┼──────────────────┼───────────────────────────────┤
│ ACID 트랜잭션     │ Aurora PostgreSQL│ order, payment, inventory,    │
│ (강한 일관성)     │ (Global Database)│ user-account, shipping,       │
│                  │                  │ warehouse, returns, seller    │
├──────────────────┼──────────────────┼───────────────────────────────┤
│ 유연한 스키마     │ DocumentDB       │ product-catalog, user-profile,│
│ (문서 모델)       │ (Global Cluster) │ wishlist, review,             │
│                  │                  │ notification, recommendation  │
├──────────────────┼──────────────────┼───────────────────────────────┤
│ 실시간 캐시       │ ElastiCache      │ cart, pricing, session,       │
│ (밀리초 응답)     │ (Valkey Global)  │ rate-limiting, leaderboard    │
├──────────────────┼──────────────────┼───────────────────────────────┤
│ 전문 검색         │ OpenSearch       │ search, analytics,            │
│ (한국어 분석)     │                  │ notification-logs             │
├──────────────────┼──────────────────┼───────────────────────────────┤
│ 이벤트 스트리밍   │ MSK (Kafka)      │ event-bus, notification,      │
│ (비동기 처리)     │                  │ analytics                     │
├──────────────────┼──────────────────┼───────────────────────────────┤
│ 정적 자산/분석    │ S3               │ CDN assets, analytics data,   │
│ (객체 저장)       │ (CRR)            │ Tempo traces                  │
└──────────────────┴──────────────────┴───────────────────────────────┘
```

---

## 1. Aurora PostgreSQL Global Database

### Cluster Topology

```
                    Global Cluster: multi-region-mall-aurora
                    ┌─────────────────────────────────────┐
                    │                                     │
        ┌───────────┴───────────┐          ┌─────────────┴──────────┐
        │     us-east-1         │          │     us-west-2          │
        │   (PRIMARY CLUSTER)   │          │  (SECONDARY CLUSTER)   │
        │                       │          │                        │
        │  Writer (r6g.2xlarge) │ ──1s──>  │  Reader 1 (r6g.xlarge) │
        │  Reader 1 (r6g.xlarge)│  lag     │  Reader 2 (r6g.xlarge) │
        │  Reader 2 (r6g.xlarge)│          │                        │
        └───────────────────────┘          └────────────────────────┘
```

### Schema Design

**users** - 사용자 계정
```sql
users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  username VARCHAR(100),
  password_hash VARCHAR(255),
  full_name VARCHAR(200),
  phone VARCHAR(20),
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP, updated_at TIMESTAMP
)
```

**orders** - 주문
```sql
orders (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  status VARCHAR(30),        -- pending, confirmed, processing, shipped, delivered, cancelled, returned
  total_amount DECIMAL(12,2),
  currency VARCHAR(3) DEFAULT 'KRW',
  shipping_address JSONB,
  created_at TIMESTAMP, updated_at TIMESTAMP
)

order_items (
  id UUID PRIMARY KEY,
  order_id UUID REFERENCES orders(id),
  product_id VARCHAR(50),
  product_name VARCHAR(200),
  quantity INTEGER,
  unit_price DECIMAL(12,2),
  total_price DECIMAL(12,2)
)
```

**payments** - 결제
```sql
payments (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL,
  amount DECIMAL(12,2),
  method VARCHAR(30),       -- credit_card, kakao_pay, naver_pay, toss, bank_transfer
  status VARCHAR(30),       -- pending, completed, refunded
  provider VARCHAR(50),     -- KG이니시스, NHN KCP, 토스페이먼츠, 카카오페이, 네이버페이
  transaction_id VARCHAR(100),
  created_at TIMESTAMP
)
```

**inventory** - 재고
```sql
inventory (
  id UUID PRIMARY KEY,
  product_id VARCHAR(50) UNIQUE,
  sku VARCHAR(50),
  quantity_available INTEGER,
  quantity_reserved INTEGER,
  warehouse_id VARCHAR(20),
  reorder_point INTEGER DEFAULT 10,
  last_restocked_at TIMESTAMP, updated_at TIMESTAMP
)
```

**shipments** - 배송
```sql
shipments (
  id UUID PRIMARY KEY,
  order_id UUID,
  carrier VARCHAR(50),       -- CJ대한통운, 한진택배, 롯데택배, 우체국택배, 로젠택배
  tracking_number VARCHAR(100),
  status VARCHAR(30),        -- preparing, in_transit, delivered
  estimated_delivery DATE,
  shipped_at TIMESTAMP, delivered_at TIMESTAMP
)
```

### Indexes
```sql
idx_orders_user_id ON orders(user_id)
idx_orders_status ON orders(status)
idx_order_items_order_id ON order_items(order_id)
idx_payments_order_id ON payments(order_id)
idx_inventory_product_id ON inventory(product_id)
idx_shipments_order_id ON shipments(order_id)
```

### Global Write Forwarding

Secondary 리전에서의 쓰기 요청은 Aurora Global Write Forwarding을 통해 Primary로 자동 라우팅됩니다.

```
[us-west-2 App] → WRITE → [us-west-2 Aurora Reader] → Forward → [us-east-1 Aurora Writer]
                                                                         │
                                                                   ≤1s replication
                                                                         │
                                                                  [us-west-2 Reader]
```

---

## 2. DocumentDB Global Cluster

### Collections

**products** (150개 상품, 10개 카테고리)
```json
{
  "productId": "PROD-001",
  "name": "삼성 갤럭시 S25 울트라",
  "brand": "삼성전자",
  "category": { "id": "CAT-01", "name": "전자제품", "slug": "electronics" },
  "price": 1799000,
  "salePrice": 1439200,
  "discount": 20,
  "currency": "KRW",
  "rating": 4.5,
  "reviewCount": 342,
  "description": "...",
  "images": ["https://cdn.mall.example.com/products/PROD-001/main.webp"],
  "tags": ["electronics", "삼성전자", "인기상품"],
  "attributes": { "weight": "0.5kg", "origin": "한국" },
  "stock": { "available": 250, "warehouse": "WH-EAST-1" },
  "status": "active"
}
```

**user_profiles** - 사용자 프로필 + 선호도
```json
{
  "userId": "a0000001-...",
  "name": "김민준",
  "tier": "gold",
  "points": 45000,
  "preferences": {
    "language": "ko",
    "currency": "KRW",
    "categories": ["electronics", "books"],
    "notificationEnabled": true
  },
  "addresses": [{ "label": "집", "city": "서울", "isDefault": true }]
}
```

**wishlists**, **reviews**, **notifications** - 위시리스트, 리뷰, 알림

### Indexes
```
products: { productId: 1 (unique) }, { category.slug: 1 }, { brand: 1 }, { price: 1 }, { rating: -1 }
user_profiles: { userId: 1 (unique) }
wishlists: { userId: 1 }
reviews: { productId: 1 }, { userId: 1 }, { rating: -1 }
notifications: { userId: 1, sentAt: -1 }
```

---

## 3. ElastiCache (Valkey) Global Datastore

### Data Patterns

| Key Pattern | TTL | Purpose |
|-------------|-----|---------|
| `product:{id}` | 1h | 상품 캐시 |
| `cache:categories` | 24h | 카테고리 목록 |
| `cart:{userId}` | 7d | 장바구니 |
| `session:{sessionId}` | 2h | 사용자 세션 |
| `user-session:{userId}` | 2h | 사용자→세션 매핑 |
| `ratelimit:api:{userId}` | 60s | API Rate Limiting |
| `stock:{productId}` | - | 실시간 재고 카운터 |
| `leaderboard:popular` | - | 인기 상품 Sorted Set |
| `search-history:{userId}` | 30d | 최근 검색어 (List) |
| `promo:flash-sale` | 24h | 플래시 세일 정보 |

### Cluster Config
- **Engine**: Valkey 7.2
- **Node Type**: cache.r7g.xlarge
- **Shards**: 3 (num_node_groups)
- **Replicas/Shard**: 2
- **Encryption**: At-rest (KMS) + In-transit (TLS)

---

## 4. OpenSearch

### Indexes

**products** - 상품 검색 (한국어 nori analyzer)
```json
{
  "settings": {
    "analysis": {
      "analyzer": {
        "korean": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase", "nori_part_of_speech_basic"]
        },
        "korean_search": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase", "synonym_filter"]
        }
      },
      "filter": {
        "synonym_filter": {
          "type": "synonym",
          "synonyms": [
            "노트북,랩탑,laptop",
            "핸드폰,스마트폰,휴대폰,phone",
            "냉장고,refrigerator,fridge"
          ]
        }
      }
    }
  }
}
```

**notification-logs** - 알림 이력 검색
**order-events** - 주문 이벤트 분석

### Cluster Config
- **Engine**: OpenSearch 2.11
- **Master Nodes**: 3 × r6g.large.search (dedicated)
- **Data Nodes**: 6 × r6g.xlarge.search
- **EBS**: 500GB gp3 per node
- **UltraWarm**: Enabled (cost optimization for old data)

---

## 5. MSK (Kafka) - Event Topics

### Topic Architecture

```
                    ┌─────────────────────────┐
                    │     Event Bus (MSK)      │
                    │                          │
  Producers         │   35 Topics              │         Consumers
  ─────────────>    │   ├── Order (4)          │    ──────────────>
  order-service     │   ├── Payment (4)        │    notification
  payment-service   │   ├── Inventory (4)      │    analytics
  inventory-service │   ├── Shipping (4)       │    search (indexing)
  user-service      │   ├── Notification (4)   │    recommendation
  ...               │   ├── User (3)           │    warehouse
                    │   ├── Product (4)        │    ...
                    │   ├── Review (2)         │
                    │   ├── Analytics (3)      │
                    │   └── Infra (2)          │    ┌──────────────┐
                    │       ├── dlq.all        │───>│ Dead Letter Q │
                    │       └── saga.orchestrator   └──────────────┘
                    └─────────────────────────┘
```

### Cross-Region Replication

```
[us-east-1 MSK] ──── MSK Replicator ────> [us-west-2 MSK]
                    (IAM Auth, async)
```

### Cluster Config
- **Instance**: kafka.m5.2xlarge × 6 brokers
- **EBS**: 1TB per broker
- **Auth**: SASL/SCRAM (port 9096)
- **Retention**: 7 days (default), 30 days (DLQ)

---

## 6. Data Flow Diagram

### Order Flow (주문 처리)

```
1. [Client] → POST /orders → [api-gateway]
2. [api-gateway] → [order-service] → Aurora: INSERT orders
3. [order-service] → Kafka: order.created
4. [payment-service] ← Kafka: order.created
5. [payment-service] → 카카오페이/토스 API → Aurora: INSERT payments
6. [payment-service] → Kafka: payment.completed
7. [inventory-service] ← Kafka: payment.completed
8. [inventory-service] → Aurora: UPDATE inventory (reserve)
9. [inventory-service] → Kafka: inventory.reserved
10. [notification-service] ← Kafka: payment.completed
11. [notification-service] → Push/Email/SMS 알림
12. [shipping-service] ← Kafka: inventory.reserved
13. [shipping-service] → Aurora: INSERT shipments → CJ대한통운 API
```

### Search Flow (상품 검색)

```
1. [Client] → GET /search?q=삼성 갤럭시 → [api-gateway]
2. [api-gateway] → [search-service]
3. [search-service] → OpenSearch: nori 분석 → "삼성" + "갤럭시"
4. [search-service] → ElastiCache: 캐시 확인
5. [search-service] ← OpenSearch: 검색 결과 (score 순)
6. [search-service] → Kafka: search.query-logged (analytics)
7. [Client] ← 검색 결과 (상품 목록 + 필터)
```

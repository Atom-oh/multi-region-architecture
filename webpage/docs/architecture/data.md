---
title: 데이터 아키텍처
sidebar_position: 4
---

# 데이터 아키텍처

Multi-Region Shopping Mall은 **Polyglot Persistence** 전략을 채택하여 각 서비스의 특성에 맞는 최적의 데이터 스토어를 사용합니다. 이 문서에서는 각 데이터 스토어의 스키마, 사용 패턴, 그리고 서비스별 데이터 매핑을 상세히 설명합니다.

## Polyglot Persistence 전략

```mermaid
flowchart TB
    subgraph Services["마이크로서비스"]
        Order[Order Service]
        Payment[Payment Service]
        Product[Product Catalog]
        Search[Search Service]
        Cart[Cart Service]
        User[User Profile]
        Review[Review Service]
        Notification[Notification]
    end

    subgraph DataStores["데이터 스토어"]
        Aurora[(Aurora PostgreSQL<br/>트랜잭션 데이터)]
        DocDB[(DocumentDB<br/>문서 데이터)]
        Cache[(ElastiCache Valkey<br/>캐시/세션)]
        OS[(OpenSearch<br/>검색/분석)]
        MSK[MSK Kafka<br/>이벤트 스트림]
    end

    Order & Payment --> Aurora
    Product & User & Review --> DocDB
    Cart --> Cache
    Search --> OS
    Order & Payment & Product --> MSK
    Notification --> DocDB & MSK
```

### 서비스별 데이터 스토어 매핑

| 서비스 | Primary Store | Secondary Store | 캐시 | 이벤트 |
|--------|--------------|-----------------|------|--------|
| **Order** | Aurora | - | ElastiCache | MSK |
| **Payment** | Aurora | - | - | MSK |
| **Inventory** | Aurora | - | ElastiCache | MSK |
| **User Account** | Aurora | - | ElastiCache | MSK |
| **Shipping** | Aurora | - | - | MSK |
| **Warehouse** | Aurora | - | - | MSK |
| **Returns** | Aurora | - | - | MSK |
| **Pricing** | Aurora | - | ElastiCache | MSK |
| **Seller** | Aurora | DocumentDB | - | MSK |
| **Product Catalog** | DocumentDB | OpenSearch | ElastiCache | MSK |
| **User Profile** | DocumentDB | - | ElastiCache | MSK |
| **Wishlist** | DocumentDB | - | - | MSK |
| **Review** | DocumentDB | OpenSearch | - | MSK |
| **Notification** | DocumentDB | - | - | MSK |
| **Search** | OpenSearch | - | ElastiCache | - |
| **Cart** | ElastiCache | - | - | MSK |
| **Recommendation** | DocumentDB | - | ElastiCache | - |
| **Analytics** | OpenSearch | Aurora | - | MSK |
| **Event Bus** | MSK | - | - | - |
| **API Gateway** | - | - | ElastiCache | - |

## Aurora PostgreSQL

### 글로벌 구성

```mermaid
flowchart LR
    subgraph Primary["us-east-1 (Primary)"]
        Writer[(Aurora Writer<br/>production-aurora-global-us-east-1)]
        Reader1[(Aurora Reader)]
    end

    subgraph Secondary["us-west-2 (Secondary)"]
        Reader2[(Aurora Reader<br/>production-aurora-global-us-west-2)]
        Reader3[(Aurora Reader)]
    end

    Writer --> Reader1
    Writer -.->|"Global DB Replication<br/>&lt;1s lag"| Reader2
    Reader2 --> Reader3
```

| 클러스터 | 리전 | 엔드포인트 | 역할 |
|----------|------|-----------|------|
| Primary | us-east-1 | `production-aurora-global-us-east-1.cluster-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com` | Writer |
| Secondary | us-west-2 | `production-aurora-global-us-west-2.cluster-yyyyyyyyyyyy.us-west-2.rds.amazonaws.com` | Reader |

### 스키마 설계

#### users 스키마

```sql
-- 사용자 계정 테이블
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    status VARCHAR(20) DEFAULT 'ACTIVE',  -- ACTIVE, SUSPENDED, DELETED
    email_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login_at TIMESTAMP WITH TIME ZONE
);

-- 사용자 주소 테이블
CREATE TABLE user_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    address_type VARCHAR(20) NOT NULL,  -- SHIPPING, BILLING
    recipient_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    address_line1 VARCHAR(255) NOT NULL,
    address_line2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL,
    country VARCHAR(50) DEFAULT 'KR',
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_user_addresses_user_id ON user_addresses(user_id);
```

#### orders 스키마

```sql
-- 주문 테이블
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    -- PENDING, CONFIRMED, PAID, PROCESSING, SHIPPED, DELIVERED, CANCELLED, REFUNDED

    -- 금액 정보
    subtotal_amount DECIMAL(15,2) NOT NULL,
    shipping_amount DECIMAL(15,2) DEFAULT 0,
    tax_amount DECIMAL(15,2) DEFAULT 0,
    discount_amount DECIMAL(15,2) DEFAULT 0,
    total_amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'KRW',

    -- 배송 정보
    shipping_address_id UUID,
    shipping_method VARCHAR(50),
    tracking_number VARCHAR(100),

    -- 타임스탬프
    ordered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    paid_at TIMESTAMP WITH TIME ZONE,
    shipped_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 주문 상품 테이블
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id),
    product_id VARCHAR(50) NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    product_image_url VARCHAR(500),
    sku VARCHAR(50),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(15,2) NOT NULL,
    discount_price DECIMAL(15,2) DEFAULT 0,
    total_price DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_ordered_at ON orders(ordered_at DESC);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
```

#### payments 스키마

```sql
-- 결제 테이블
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL,
    payment_number VARCHAR(50) UNIQUE NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    -- PENDING, PROCESSING, COMPLETED, FAILED, CANCELLED, REFUNDED

    -- 결제 정보
    payment_method VARCHAR(30) NOT NULL,  -- CREDIT_CARD, BANK_TRANSFER, KAKAO_PAY, NAVER_PAY
    payment_gateway VARCHAR(30),  -- TOSS, INICIS, KAKAO, NAVER

    -- 금액
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'KRW',

    -- 외부 결제 정보
    external_transaction_id VARCHAR(100),
    pg_response_code VARCHAR(20),
    pg_response_message VARCHAR(255),

    -- 타임스탬프
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    refunded_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 환불 테이블
CREATE TABLE refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID NOT NULL REFERENCES payments(id),
    refund_number VARCHAR(50) UNIQUE NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    amount DECIMAL(15,2) NOT NULL,
    reason VARCHAR(500),
    external_refund_id VARCHAR(100),
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_payments_order_id ON payments(order_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_refunds_payment_id ON refunds(payment_id);
```

#### inventory 스키마

```sql
-- 재고 테이블
CREATE TABLE inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id VARCHAR(50) NOT NULL,
    sku VARCHAR(50) NOT NULL,
    warehouse_id UUID NOT NULL,

    -- 수량
    total_quantity INTEGER NOT NULL DEFAULT 0,
    available_quantity INTEGER NOT NULL DEFAULT 0,
    reserved_quantity INTEGER NOT NULL DEFAULT 0,

    -- 임계값
    reorder_point INTEGER DEFAULT 10,
    reorder_quantity INTEGER DEFAULT 100,

    -- 메타데이터
    last_restocked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    UNIQUE(product_id, sku, warehouse_id)
);

-- 재고 이동 기록
CREATE TABLE inventory_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_id UUID NOT NULL REFERENCES inventory(id),
    movement_type VARCHAR(30) NOT NULL,
    -- INBOUND, OUTBOUND, RESERVED, RELEASED, ADJUSTMENT
    quantity INTEGER NOT NULL,
    reference_type VARCHAR(30),  -- ORDER, RETURN, ADJUSTMENT, TRANSFER
    reference_id VARCHAR(50),
    notes VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_inventory_product ON inventory(product_id, sku);
CREATE INDEX idx_inventory_warehouse ON inventory(warehouse_id);
CREATE INDEX idx_inventory_movements_inventory_id ON inventory_movements(inventory_id);
```

#### shipments 스키마

```sql
-- 배송 테이블
CREATE TABLE shipments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL,
    shipment_number VARCHAR(50) UNIQUE NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    -- PENDING, PICKED, PACKED, SHIPPED, IN_TRANSIT, OUT_FOR_DELIVERY, DELIVERED, FAILED

    -- 배송사 정보
    carrier VARCHAR(50) NOT NULL,  -- CJ대한통운, 롯데택배, 한진택배, 우체국
    tracking_number VARCHAR(100),

    -- 주소 정보
    recipient_name VARCHAR(100) NOT NULL,
    recipient_phone VARCHAR(20) NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    address VARCHAR(500) NOT NULL,

    -- 배송 옵션
    shipping_method VARCHAR(30),  -- STANDARD, EXPRESS, SAME_DAY
    estimated_delivery_date DATE,
    actual_delivery_date DATE,

    -- 타임스탬프
    picked_at TIMESTAMP WITH TIME ZONE,
    shipped_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 배송 추적 이벤트
CREATE TABLE shipment_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_id UUID NOT NULL REFERENCES shipments(id),
    event_type VARCHAR(50) NOT NULL,
    location VARCHAR(255),
    description VARCHAR(500),
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_shipments_order_id ON shipments(order_id);
CREATE INDEX idx_shipments_tracking ON shipments(carrier, tracking_number);
CREATE INDEX idx_shipment_events_shipment_id ON shipment_events(shipment_id);
```

## DocumentDB

### 글로벌 구성

```mermaid
flowchart LR
    subgraph Primary["us-east-1 (Primary)"]
        Primary_W[(DocumentDB Primary<br/>production-docdb-global-primary)]
        Primary_R1[(Replica)]
    end

    subgraph Secondary["us-west-2 (Secondary)"]
        Secondary_W[(DocumentDB Secondary<br/>production-docdb-global-us-west-2)]
        Secondary_R1[(Replica)]
    end

    Primary_W --> Primary_R1
    Primary_W -.->|"Global Cluster Replication<br/>&lt;1s lag"| Secondary_W
    Secondary_W --> Secondary_R1
```

| 클러스터 | 리전 | 엔드포인트 | 역할 |
|----------|------|-----------|------|
| Primary | us-east-1 | `production-docdb-global-primary.cluster-xxxxxxxxxxxx.us-east-1.docdb.amazonaws.com` | Writer |
| Secondary | us-west-2 | `production-docdb-global-us-west-2.cluster-yyyyyyyyyyyy.us-west-2.docdb.amazonaws.com` | Reader |

### 컬렉션 스키마

#### products 컬렉션

```javascript
// products 컬렉션 스키마
{
  "_id": ObjectId("..."),
  "productId": "PROD-001",
  "name": "삼성 갤럭시 S24 울트라",
  "slug": "samsung-galaxy-s24-ultra",
  "brand": "Samsung",
  "category": {
    "main": "전자제품",
    "sub": "스마트폰",
    "path": ["전자제품", "스마트폰", "Android"]
  },
  "description": {
    "short": "AI 기능이 탑재된 플래그십 스마트폰",
    "long": "상세한 제품 설명...",
    "highlights": ["200MP 카메라", "Galaxy AI", "S Pen 내장"]
  },
  "pricing": {
    "listPrice": 1650000,
    "salePrice": 1550000,
    "currency": "KRW",
    "discount": {
      "percentage": 6,
      "validUntil": ISODate("2024-12-31T23:59:59Z")
    }
  },
  "variants": [
    {
      "sku": "S24U-256-BLK",
      "attributes": {
        "storage": "256GB",
        "color": "Titanium Black"
      },
      "price": 1550000,
      "stock": 150
    },
    {
      "sku": "S24U-512-VLT",
      "attributes": {
        "storage": "512GB",
        "color": "Titanium Violet"
      },
      "price": 1750000,
      "stock": 80
    }
  ],
  "images": [
    {
      "url": "https://cdn.atomai.click/products/s24u-main.jpg",
      "alt": "Galaxy S24 Ultra 정면",
      "type": "main"
    }
  ],
  "specifications": {
    "display": "6.8인치 QHD+ Dynamic AMOLED 2X",
    "processor": "Snapdragon 8 Gen 3",
    "ram": "12GB",
    "battery": "5000mAh",
    "os": "Android 14"
  },
  "seller": {
    "sellerId": "SELLER-001",
    "name": "Samsung 공식스토어",
    "rating": 4.9
  },
  "ratings": {
    "average": 4.7,
    "count": 2584,
    "distribution": {
      "5": 1842,
      "4": 512,
      "3": 156,
      "2": 48,
      "1": 26
    }
  },
  "tags": ["5G", "AI", "플래그십", "S펜", "고성능"],
  "status": "ACTIVE",  // ACTIVE, DRAFT, DISCONTINUED
  "createdAt": ISODate("2024-01-15T09:00:00Z"),
  "updatedAt": ISODate("2024-03-10T14:30:00Z")
}

// 인덱스
db.products.createIndex({ "productId": 1 }, { unique: true })
db.products.createIndex({ "slug": 1 }, { unique: true })
db.products.createIndex({ "category.main": 1, "category.sub": 1 })
db.products.createIndex({ "seller.sellerId": 1 })
db.products.createIndex({ "status": 1 })
db.products.createIndex({ "pricing.salePrice": 1 })
db.products.createIndex({ "ratings.average": -1 })
db.products.createIndex({ "tags": 1 })
```

#### user_profiles 컬렉션

```javascript
// user_profiles 컬렉션 스키마
{
  "_id": ObjectId("..."),
  "userId": "USER-001",  // Aurora users.id 참조
  "displayName": "홍길동",
  "avatar": "https://cdn.atomai.click/avatars/user001.jpg",
  "preferences": {
    "language": "ko",
    "currency": "KRW",
    "timezone": "Asia/Seoul",
    "notifications": {
      "email": true,
      "push": true,
      "sms": false,
      "marketing": true
    },
    "categories": ["전자제품", "패션", "도서"]
  },
  "recentlyViewed": [
    {
      "productId": "PROD-001",
      "viewedAt": ISODate("2024-03-10T10:30:00Z")
    }
  ],
  "searchHistory": [
    {
      "query": "갤럭시 S24",
      "searchedAt": ISODate("2024-03-10T10:25:00Z")
    }
  ],
  "savedPaymentMethods": [
    {
      "id": "PM-001",
      "type": "CREDIT_CARD",
      "last4": "1234",
      "brand": "VISA",
      "isDefault": true
    }
  ],
  "createdAt": ISODate("2024-01-01T00:00:00Z"),
  "updatedAt": ISODate("2024-03-10T10:30:00Z")
}

// 인덱스
db.user_profiles.createIndex({ "userId": 1 }, { unique: true })
db.user_profiles.createIndex({ "preferences.categories": 1 })
```

#### wishlists 컬렉션

```javascript
// wishlists 컬렉션 스키마
{
  "_id": ObjectId("..."),
  "wishlistId": "WL-001",
  "userId": "USER-001",
  "name": "나의 위시리스트",
  "isPublic": false,
  "items": [
    {
      "productId": "PROD-001",
      "addedAt": ISODate("2024-03-05T14:00:00Z"),
      "priceAtAdd": 1550000,
      "note": "생일선물로 받고 싶어요"
    },
    {
      "productId": "PROD-042",
      "addedAt": ISODate("2024-03-08T09:30:00Z"),
      "priceAtAdd": 89000,
      "note": null
    }
  ],
  "createdAt": ISODate("2024-02-01T00:00:00Z"),
  "updatedAt": ISODate("2024-03-08T09:30:00Z")
}

// 인덱스
db.wishlists.createIndex({ "userId": 1 })
db.wishlists.createIndex({ "items.productId": 1 })
```

#### reviews 컬렉션

```javascript
// reviews 컬렉션 스키마
{
  "_id": ObjectId("..."),
  "reviewId": "REV-001",
  "productId": "PROD-001",
  "orderId": "ORD-12345",  // 구매 검증용
  "userId": "USER-001",
  "userDisplayName": "홍*동",
  "rating": 5,
  "title": "최고의 스마트폰!",
  "content": "Galaxy AI 기능이 정말 유용합니다. 특히 통화 번역 기능이...",
  "images": [
    {
      "url": "https://cdn.atomai.click/reviews/rev001-1.jpg",
      "caption": "박스 개봉"
    }
  ],
  "pros": ["뛰어난 카메라", "S펜 편리함", "AI 기능"],
  "cons": ["가격이 비쌈"],
  "isVerifiedPurchase": true,
  "helpfulCount": 42,
  "status": "APPROVED",  // PENDING, APPROVED, REJECTED
  "createdAt": ISODate("2024-02-15T16:30:00Z"),
  "updatedAt": ISODate("2024-02-15T16:30:00Z")
}

// 인덱스
db.reviews.createIndex({ "productId": 1, "createdAt": -1 })
db.reviews.createIndex({ "userId": 1 })
db.reviews.createIndex({ "rating": 1 })
db.reviews.createIndex({ "status": 1 })
```

#### notifications 컬렉션

```javascript
// notifications 컬렉션 스키마
{
  "_id": ObjectId("..."),
  "notificationId": "NOTIF-001",
  "userId": "USER-001",
  "type": "ORDER_STATUS",  // ORDER_STATUS, PROMOTION, PRICE_DROP, REVIEW_REQUEST, SYSTEM
  "channel": "PUSH",  // PUSH, EMAIL, SMS, IN_APP
  "title": "주문이 배송되었습니다",
  "body": "주문번호 ORD-12345가 배송을 시작했습니다.",
  "data": {
    "orderId": "ORD-12345",
    "trackingNumber": "1234567890",
    "deepLink": "/orders/ORD-12345"
  },
  "status": "SENT",  // PENDING, SENT, DELIVERED, FAILED, READ
  "scheduledAt": null,
  "sentAt": ISODate("2024-03-10T14:00:00Z"),
  "readAt": null,
  "createdAt": ISODate("2024-03-10T14:00:00Z")
}

// 인덱스
db.notifications.createIndex({ "userId": 1, "createdAt": -1 })
db.notifications.createIndex({ "status": 1 })
db.notifications.createIndex({ "type": 1 })
db.notifications.createIndex({ "scheduledAt": 1 }, { sparse: true })
```

## ElastiCache Valkey

### 글로벌 구성

```mermaid
flowchart LR
    subgraph Primary["us-east-1 (Primary)"]
        P_Node1[Node 1]
        P_Node2[Node 2]
        P_Node3[Node 3]
    end

    subgraph Secondary["us-west-2 (Replica)"]
        S_Node1[Node 1]
        S_Node2[Node 2]
        S_Node3[Node 3]
    end

    P_Node1 & P_Node2 & P_Node3 -.->|"Global Datastore<br/>sub-second lag"| S_Node1 & S_Node2 & S_Node3
```

| 클러스터 | 리전 | 엔드포인트 | 역할 |
|----------|------|-----------|------|
| Primary | us-east-1 | `clustercfg.production-elasticache-us-east-1.xxxxxx.use1.cache.amazonaws.com:6379` | Primary |
| Secondary | us-west-2 | `clustercfg.production-elasticache-us-west-2.yyyyyy.usw2.cache.amazonaws.com:6379` | Replica |

### 키 패턴 및 TTL

| 키 패턴 | 데이터 | TTL | 용도 |
|---------|--------|-----|------|
| `cart:{userId}` | 장바구니 JSON | 7일 | 장바구니 데이터 |
| `session:{sessionId}` | 세션 JSON | 24시간 | 사용자 세션 |
| `product:{productId}` | 상품 JSON | 1시간 | 상품 캐시 |
| `product:list:{category}:{page}` | 상품 목록 | 10분 | 카테고리별 목록 |
| `user:{userId}:profile` | 프로필 JSON | 30분 | 사용자 프로필 캐시 |
| `inventory:{productId}:{sku}` | 재고 수량 | 5분 | 재고 캐시 |
| `price:{productId}` | 가격 정보 | 15분 | 가격 캐시 |
| `rate_limit:{userId}:{endpoint}` | 카운터 | 1분 | Rate limiting |
| `search:suggest:{prefix}` | 자동완성 리스트 | 1시간 | 검색 자동완성 |

### 데이터 구조 예시

#### 장바구니 (cart:{userId})

```json
{
  "userId": "USER-001",
  "items": [
    {
      "productId": "PROD-001",
      "sku": "S24U-256-BLK",
      "name": "삼성 갤럭시 S24 울트라 256GB",
      "quantity": 1,
      "unitPrice": 1550000,
      "totalPrice": 1550000,
      "imageUrl": "https://cdn.atomai.click/products/s24u-thumb.jpg"
    }
  ],
  "subtotal": 1550000,
  "itemCount": 1,
  "updatedAt": "2024-03-10T14:30:00Z"
}
```

#### 세션 (session:{sessionId})

```json
{
  "sessionId": "sess_abc123xyz",
  "userId": "USER-001",
  "email": "user@example.com",
  "roles": ["USER"],
  "deviceInfo": {
    "type": "mobile",
    "os": "iOS",
    "browser": "Safari"
  },
  "region": "us-west-2",
  "createdAt": "2024-03-10T10:00:00Z",
  "lastAccessAt": "2024-03-10T14:30:00Z"
}
```

### Valkey 명령어 예시

```bash
# 장바구니 조회
GET cart:USER-001

# 장바구니 업데이트 (7일 TTL)
SET cart:USER-001 '{"items":[...]}' EX 604800

# 재고 감소 (원자적 연산)
DECRBY inventory:PROD-001:S24U-256-BLK 1

# Rate limiting (1분에 100회 제한)
MULTI
INCR rate_limit:USER-001:POST:/orders
EXPIRE rate_limit:USER-001:POST:/orders 60
EXEC

# 검색 자동완성
ZADD search:suggest:갤 1 "갤럭시 S24" 2 "갤럭시 버즈" 3 "갤럭시 탭"
ZRANGE search:suggest:갤 0 9
```

## OpenSearch

### 리전별 구성

OpenSearch는 리전별로 독립적인 클러스터를 운영합니다 (글로벌 복제 없음).

| 리전 | 도메인 | 엔드포인트 |
|------|--------|-----------|
| us-east-1 | production-os-use1 | `vpc-production-os-use1-xxxxxxxxxxxxxxxxxxxxxxxxxxxx.us-east-1.es.amazonaws.com` |
| us-west-2 | production-os-usw2 | `vpc-production-os-usw2-yyyyyyyyyyyyyyyyyyyyyyyyyyyy.us-west-2.es.amazonaws.com` |

### 인덱스 매핑

#### products 인덱스

```json
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "analysis": {
      "analyzer": {
        "korean_analyzer": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": [
            "nori_readingform",
            "lowercase",
            "nori_part_of_speech"
          ]
        },
        "korean_search": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": [
            "nori_readingform",
            "lowercase",
            "synonym_filter"
          ]
        }
      },
      "filter": {
        "synonym_filter": {
          "type": "synonym",
          "synonyms": [
            "핸드폰,휴대폰,스마트폰,폰",
            "노트북,랩탑,laptop",
            "이어폰,이어버드,earbuds"
          ]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "productId": { "type": "keyword" },
      "name": {
        "type": "text",
        "analyzer": "korean_analyzer",
        "search_analyzer": "korean_search",
        "fields": {
          "keyword": { "type": "keyword" },
          "suggest": {
            "type": "completion",
            "analyzer": "korean_analyzer"
          }
        }
      },
      "brand": {
        "type": "text",
        "fields": {
          "keyword": { "type": "keyword" }
        }
      },
      "category": {
        "properties": {
          "main": { "type": "keyword" },
          "sub": { "type": "keyword" },
          "path": { "type": "keyword" }
        }
      },
      "description": {
        "type": "text",
        "analyzer": "korean_analyzer"
      },
      "tags": { "type": "keyword" },
      "price": { "type": "float" },
      "salePrice": { "type": "float" },
      "rating": { "type": "float" },
      "reviewCount": { "type": "integer" },
      "sellerId": { "type": "keyword" },
      "status": { "type": "keyword" },
      "createdAt": { "type": "date" },
      "updatedAt": { "type": "date" }
    }
  }
}
```

#### notification-logs 인덱스

```json
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1,
    "index.lifecycle.name": "notification-logs-policy",
    "index.lifecycle.rollover_alias": "notification-logs"
  },
  "mappings": {
    "properties": {
      "notificationId": { "type": "keyword" },
      "userId": { "type": "keyword" },
      "type": { "type": "keyword" },
      "channel": { "type": "keyword" },
      "status": { "type": "keyword" },
      "title": { "type": "text" },
      "sentAt": { "type": "date" },
      "deliveredAt": { "type": "date" },
      "errorMessage": { "type": "text" },
      "@timestamp": { "type": "date" }
    }
  }
}
```

### 검색 쿼리 예시

```json
// 한국어 상품 검색
POST /products/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "multi_match": {
            "query": "갤럭시 스마트폰",
            "fields": ["name^3", "brand^2", "description", "tags"],
            "type": "best_fields",
            "fuzziness": "AUTO"
          }
        }
      ],
      "filter": [
        { "term": { "status": "ACTIVE" } },
        { "range": { "price": { "gte": 100000, "lte": 2000000 } } }
      ]
    }
  },
  "sort": [
    { "_score": "desc" },
    { "rating": "desc" }
  ],
  "aggs": {
    "categories": {
      "terms": { "field": "category.main" }
    },
    "price_ranges": {
      "range": {
        "field": "price",
        "ranges": [
          { "to": 100000 },
          { "from": 100000, "to": 500000 },
          { "from": 500000, "to": 1000000 },
          { "from": 1000000 }
        ]
      }
    },
    "avg_rating": {
      "avg": { "field": "rating" }
    }
  },
  "highlight": {
    "fields": {
      "name": {},
      "description": { "fragment_size": 150 }
    }
  }
}
```

## 데이터 동기화 패턴

```mermaid
flowchart TB
    subgraph Sources["Source of Truth"]
        Aurora[(Aurora)]
        DocDB[(DocumentDB)]
    end

    subgraph Sync["동기화"]
        Kafka[MSK Kafka]
        CDC[Change Stream]
    end

    subgraph Derived["파생 데이터"]
        Cache[(ElastiCache)]
        OS[(OpenSearch)]
    end

    Aurora -->|Order Events| Kafka
    DocDB -->|Product Changes| CDC
    CDC --> Kafka
    Kafka -->|Consumer| Cache
    Kafka -->|Consumer| OS
```

### DocumentDB Change Stream → OpenSearch

```python
# Change Stream Consumer
async def sync_products_to_opensearch():
    client = motor.motor_asyncio.AsyncIOMotorClient(DOCDB_URI)
    collection = client.mall.products

    pipeline = [
        {'$match': {'operationType': {'$in': ['insert', 'update', 'replace']}}}
    ]

    async with collection.watch(pipeline) as stream:
        async for change in stream:
            doc = change['fullDocument']
            await opensearch.index(
                index='products',
                id=doc['productId'],
                body={
                    'productId': doc['productId'],
                    'name': doc['name'],
                    'brand': doc['brand'],
                    'category': doc['category'],
                    'description': doc['description']['short'],
                    'tags': doc['tags'],
                    'price': doc['pricing']['listPrice'],
                    'salePrice': doc['pricing']['salePrice'],
                    'rating': doc['ratings']['average'],
                    'reviewCount': doc['ratings']['count'],
                    'sellerId': doc['seller']['sellerId'],
                    'status': doc['status'],
                    'updatedAt': doc['updatedAt']
                }
            )
```

## 다음 단계

- [이벤트 기반 아키텍처](./event-driven) - MSK Kafka 토픽 및 이벤트 패턴
- [재해 복구](./disaster-recovery) - 데이터 복제 및 페일오버

---
sidebar_position: 2
title: DocumentDB Global Cluster
description: DocumentDB Global Cluster 구성, Change Stream, 컬렉션 설계
---

# DocumentDB Global Cluster

멀티 리전 쇼핑몰 플랫폼은 **Amazon DocumentDB Global Cluster**를 사용하여 MongoDB 호환 문서 데이터베이스를 운영합니다. 상품 카탈로그, 사용자 프로필, 위시리스트, 리뷰 등 비정형 데이터를 저장합니다.

## 아키텍처

```mermaid
flowchart TB
    subgraph "us-east-1 (Primary)"
        GC["Global Cluster<br/>production-docdb-global"]
        subgraph "Primary Cluster"
            P1["Primary<br/>db.r6g.xlarge"]
            R1["Replica 1<br/>db.r6g.xlarge"]
            R2["Replica 2<br/>db.r6g.xlarge"]
        end
    end

    subgraph "us-west-2 (Secondary)"
        subgraph "Secondary Cluster"
            SP1["Primary<br/>db.r6g.xlarge"]
            SR1["Replica 1<br/>db.r6g.xlarge"]
            SR2["Replica 2<br/>db.r6g.xlarge"]
        end
    end

    subgraph "Change Stream"
        CS["Change Stream Consumer"]
        OS["OpenSearch"]
    end

    GC --> P1
    P1 -.->|"동기 복제"| R1
    P1 -.->|"동기 복제"| R2
    P1 -.->|"비동기 복제"| SP1
    SP1 -.->|"동기 복제"| SR1
    SP1 -.->|"동기 복제"| SR2

    P1 -->|"Change Stream"| CS
    CS -->|"색인 동기화"| OS
```

## 클러스터 사양

| 항목 | us-east-1 (Primary) | us-west-2 (Secondary) |
|------|---------------------|----------------------|
| 클러스터 ID | `production-docdb-global-primary` | `production-docdb-global-us-west-2` |
| 엔진 버전 | DocumentDB 5.0 | DocumentDB 5.0 |
| 인스턴스 클래스 | db.r6g.xlarge | db.r6g.xlarge |
| 인스턴스 수 | 3 | 3 |
| 암호화 | KMS (at-rest) + TLS (in-transit) | KMS + TLS |

:::info 참고
us-east-1의 프라이머리 클러스터는 스냅샷에서 복원된 `production-docdb-global-primary` 클러스터입니다. 원래 `production-docdb-global-us-east-1` 클러스터를 글로벌 클러스터로 변환할 수 없어 새로 생성했습니다.
:::

## 연결 엔드포인트

### us-east-1

| 엔드포인트 유형 | 값 |
|---------------|-----|
| **Primary** | `production-docdb-global-us-east-1.cluster-xxxxxxxxxxxx.us-east-1.docdb.amazonaws.com` |
| **Reader** | `production-docdb-global-us-east-1.cluster-ro-xxxxxxxxxxxx.us-east-1.docdb.amazonaws.com` |
| 포트 | 27017 |

### us-west-2

| 엔드포인트 유형 | 값 |
|---------------|-----|
| **Primary** | `production-docdb-global-us-west-2.cluster-yyyyyyyyyyyy.us-west-2.docdb.amazonaws.com` |
| **Reader** | `production-docdb-global-us-west-2.cluster-ro-yyyyyyyyyyyy.us-west-2.docdb.amazonaws.com` |
| 포트 | 27017 |

## Terraform 구성

```hcl
resource "aws_docdb_cluster" "this" {
  cluster_identifier        = local.cluster_identifier
  global_cluster_identifier = var.is_primary ? null : var.global_cluster_identifier

  engine         = "docdb"
  engine_version = "5.0.0"

  # Primary cluster credentials
  master_username = var.is_primary ? "docdb_admin" : null
  master_password = var.is_primary ? var.master_password : null

  db_subnet_group_name            = aws_docdb_subnet_group.this.name
  db_cluster_parameter_group_name = var.is_primary ? aws_docdb_cluster_parameter_group.this.name : null
  vpc_security_group_ids          = [var.security_group_id]

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  enabled_cloudwatch_logs_exports = var.is_primary ? ["audit", "profiler"] : []

  deletion_protection          = true
  backup_retention_period      = var.is_primary ? 35 : 1
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
}

resource "aws_docdb_cluster_instance" "this" {
  count = var.instance_count  # 3

  identifier         = "${local.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.this.id
  instance_class     = var.instance_class  # db.r6g.xlarge
}
```

### 파라미터 그룹

```hcl
resource "aws_docdb_cluster_parameter_group" "this" {
  family      = "docdb5.0"
  name        = "${var.environment}-docdb-global-${var.region}"
  description = "DocumentDB cluster parameter group"

  parameter {
    name  = "tls"
    value = "enabled"
  }

  parameter {
    name  = "audit_logs"
    value = "enabled"
  }

  parameter {
    name  = "profiler"
    value = "enabled"
  }

  parameter {
    name  = "profiler_threshold_ms"
    value = "100"
  }
}
```

## 컬렉션 설계

### products 컬렉션

상품 카탈로그 데이터를 저장합니다.

```javascript
// products collection
{
  _id: ObjectId("..."),
  productId: "PROD-001",
  name: "삼성 갤럭시 S24 Ultra",
  nameKo: "삼성 갤럭시 S24 울트라",
  category: {
    main: "electronics",
    sub: "smartphones",
    path: ["electronics", "mobile", "smartphones"]
  },
  brand: "Samsung",
  price: {
    amount: 1650000,
    currency: "KRW",
    discountPercent: 10
  },
  inventory: {
    totalStock: 500,
    availableStock: 423
  },
  attributes: {
    color: ["블랙", "화이트", "퍼플"],
    storage: ["256GB", "512GB", "1TB"],
    display: "6.8인치 Dynamic AMOLED"
  },
  images: [
    { url: "https://...", type: "main" },
    { url: "https://...", type: "gallery" }
  ],
  rating: {
    average: 4.7,
    count: 2341
  },
  createdAt: ISODate("2024-01-15T00:00:00Z"),
  updatedAt: ISODate("2024-03-01T00:00:00Z"),
  status: "active"
}

// Indexes
db.products.createIndex({ productId: 1 }, { unique: true })
db.products.createIndex({ "category.path": 1 })
db.products.createIndex({ brand: 1 })
db.products.createIndex({ "price.amount": 1 })
db.products.createIndex({ status: 1, updatedAt: -1 })
db.products.createIndex({ name: "text", nameKo: "text" })
```

### user_profiles 컬렉션

사용자 프로필 및 설정을 저장합니다.

```javascript
// user_profiles collection
{
  _id: ObjectId("..."),
  userId: "USER-001",
  preferences: {
    language: "ko",
    currency: "KRW",
    notifications: {
      email: true,
      push: true,
      sms: false
    }
  },
  addresses: [
    {
      id: "ADDR-001",
      type: "shipping",
      isDefault: true,
      name: "홍길동",
      phone: "010-1234-5678",
      zipCode: "06234",
      address1: "서울특별시 강남구 테헤란로 123",
      address2: "101동 1001호"
    }
  ],
  paymentMethods: [
    {
      id: "PM-001",
      type: "card",
      isDefault: true,
      last4: "1234",
      brand: "visa"
    }
  ],
  recentlyViewed: [
    { productId: "PROD-001", viewedAt: ISODate("...") }
  ],
  createdAt: ISODate("..."),
  updatedAt: ISODate("...")
}

// Indexes
db.user_profiles.createIndex({ userId: 1 }, { unique: true })
db.user_profiles.createIndex({ "addresses.zipCode": 1 })
```

### wishlists 컬렉션

```javascript
// wishlists collection
{
  _id: ObjectId("..."),
  userId: "USER-001",
  items: [
    {
      productId: "PROD-001",
      addedAt: ISODate("..."),
      priceAtAdd: 1650000,
      notifyOnSale: true
    }
  ],
  createdAt: ISODate("..."),
  updatedAt: ISODate("...")
}

// Indexes
db.wishlists.createIndex({ userId: 1 }, { unique: true })
db.wishlists.createIndex({ "items.productId": 1 })
```

### reviews 컬렉션

```javascript
// reviews collection
{
  _id: ObjectId("..."),
  reviewId: "REV-001",
  productId: "PROD-001",
  userId: "USER-001",
  orderId: "ORD-001",
  rating: 5,
  title: "최고의 스마트폰",
  content: "화면이 정말 선명하고 카메라 성능이 뛰어납니다...",
  images: ["https://..."],
  helpful: {
    count: 42,
    users: ["USER-002", "USER-003"]
  },
  verified: true,
  createdAt: ISODate("..."),
  updatedAt: ISODate("...")
}

// Indexes
db.reviews.createIndex({ productId: 1, createdAt: -1 })
db.reviews.createIndex({ userId: 1 })
db.reviews.createIndex({ rating: 1 })
```

### notifications 컬렉션

```javascript
// notifications collection
{
  _id: ObjectId("..."),
  userId: "USER-001",
  type: "order_shipped",
  title: "주문하신 상품이 배송 시작되었습니다",
  body: "주문번호 ORD-001의 배송이 시작되었습니다...",
  data: {
    orderId: "ORD-001",
    trackingNumber: "1234567890"
  },
  read: false,
  createdAt: ISODate("..."),
  expiresAt: ISODate("...")  // TTL index
}

// Indexes
db.notifications.createIndex({ userId: 1, read: 1, createdAt: -1 })
db.notifications.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 })
```

## Change Stream

DocumentDB Change Stream을 사용하여 데이터 변경을 OpenSearch로 동기화합니다.

```mermaid
sequenceDiagram
    participant App as Application
    participant DocDB as DocumentDB
    participant Consumer as Change Stream Consumer
    participant OS as OpenSearch

    App->>DocDB: Insert/Update Product
    DocDB->>Consumer: Change Event
    Consumer->>Consumer: Transform Document
    Consumer->>OS: Index Document
    OS-->>Consumer: Acknowledge
```

### Change Stream Consumer 예시 (Go)

```go
// changestream_consumer.go
func watchProducts(ctx context.Context, collection *mongo.Collection) {
    pipeline := mongo.Pipeline{
        bson.D{{Key: "$match", Value: bson.D{
            {Key: "operationType", Value: bson.D{
                {Key: "$in", Value: []string{"insert", "update", "replace"}},
            }},
        }}},
    }

    opts := options.ChangeStream().
        SetFullDocument(options.UpdateLookup).
        SetStartAtOperationTime(&primitive.Timestamp{T: uint32(time.Now().Unix())})

    stream, err := collection.Watch(ctx, pipeline, opts)
    if err != nil {
        log.Fatal(err)
    }
    defer stream.Close(ctx)

    for stream.Next(ctx) {
        var event bson.M
        if err := stream.Decode(&event); err != nil {
            continue
        }

        // Index to OpenSearch
        indexToOpenSearch(event["fullDocument"])
    }
}
```

## 모니터링

### CloudWatch 메트릭

| 메트릭 | 설명 | 알람 임계값 |
|--------|------|-----------|
| CPUUtilization | CPU 사용률 | > 80% |
| FreeableMemory | 사용 가능한 메모리 | < 1GB |
| DatabaseConnections | 활성 연결 수 | > 500 |
| ReadLatency | 읽기 지연 | > 20ms |
| WriteLatency | 쓰기 지연 | > 50ms |

### 프로파일러

100ms 이상 걸리는 쿼리를 자동으로 로깅합니다:

```javascript
// 느린 쿼리 확인
db.system.profile.find({
  millis: { $gt: 100 }
}).sort({ ts: -1 }).limit(10)
```

## 다음 단계

- [ElastiCache Global Datastore](/infrastructure/databases/elasticache-global) - Valkey 캐시
- [OpenSearch](/infrastructure/databases/opensearch) - 검색 엔진

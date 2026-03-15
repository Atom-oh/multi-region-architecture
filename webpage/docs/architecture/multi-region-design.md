---
title: 멀티리전 설계
sidebar_position: 2
---

# 멀티리전 설계

Multi-Region Shopping Mall은 **Write-Primary/Read-Local** 패턴을 기반으로 한 Active-Active 멀티리전 아키텍처를 구현합니다. 이 문서에서는 왜 이 패턴을 선택했는지, 어떻게 동작하는지, 그리고 일관성 모델에 대해 상세히 설명합니다.

## 리전 역할 할당

| 리전 | 역할 | 책임 |
|------|------|------|
| **us-east-1** | Primary | 모든 쓰기 작업, 글로벌 데이터 마스터 |
| **us-west-2** | Secondary | 읽기 작업, 쓰기 전달, 장애 시 승격 가능 |

```mermaid
flowchart TB
    subgraph Primary["us-east-1 (Primary Region)"]
        direction TB
        P_EKS[EKS Cluster]
        P_Aurora[(Aurora Writer)]
        P_DocDB[(DocumentDB Primary)]
        P_Cache[(ElastiCache Primary)]
        P_MSK[MSK Kafka]
    end

    subgraph Secondary["us-west-2 (Secondary Region)"]
        direction TB
        S_EKS[EKS Cluster]
        S_Aurora[(Aurora Reader)]
        S_DocDB[(DocumentDB Secondary)]
        S_Cache[(ElastiCache Replica)]
        S_MSK[MSK Kafka]
    end

    P_Aurora -.->|"Global DB Replication"| S_Aurora
    P_DocDB -.->|"Global Cluster Replication"| S_DocDB
    P_Cache -.->|"Global Datastore"| S_Cache
    P_MSK <-.->|"MSK Replicator"| S_MSK

    P_EKS --> P_Aurora & P_DocDB & P_Cache & P_MSK
    S_EKS --> S_Aurora & S_DocDB & S_Cache & S_MSK
    S_EKS -.->|"Write Forwarding"| P_EKS
```

## Why Active-Active?

### 비교: Active-Passive vs Active-Active

| 항목 | Active-Passive | Active-Active |
|------|----------------|---------------|
| **리소스 활용** | Secondary 유휴 상태 | 양쪽 리전 모두 활용 |
| **읽기 지연시간** | 단일 리전 의존 | 사용자 근처 리전에서 처리 |
| **페일오버 시간** | DNS 전파 대기 (수 분) | 즉시 (이미 트래픽 처리 중) |
| **비용 효율성** | 낮음 (대기 리소스) | 높음 (평상시 부하 분산) |
| **구현 복잡도** | 낮음 | 높음 (데이터 일관성 관리) |

### Active-Active 선택 이유

1. **99.99% 가용성 목표**: 단일 리전 장애에도 서비스 지속
2. **글로벌 사용자 경험**: 사용자에게 가장 가까운 리전에서 응답
3. **비용 최적화**: 양쪽 리전 리소스를 평상시에도 활용
4. **점진적 페일오버**: 트래픽이 이미 분산되어 있어 전환이 매끄러움

## Write-Primary / Read-Local 패턴

### 패턴 개요

```mermaid
flowchart TB
    subgraph Client["Client Request"]
        Read[GET /products<br/>GET /orders]
        Write[POST /orders<br/>PUT /cart]
    end

    subgraph Routing["Route 53 Latency Routing"]
        R53[atomai.click]
    end

    subgraph Primary["us-east-1"]
        USE_EKS[EKS]
        USE_DB[(Primary DB)]
    end

    subgraph Secondary["us-west-2"]
        USW_EKS[EKS]
        USW_DB[(Replica DB)]
    end

    Read --> R53
    Write --> R53

    R53 -->|"Latency-based"| USE_EKS
    R53 -->|"Latency-based"| USW_EKS

    USE_EKS -->|"Read/Write"| USE_DB
    USW_EKS -->|"Read"| USW_DB
    USW_EKS -.->|"Write Forward"| USE_EKS

    USE_DB -.->|"Replication"| USW_DB
```

### Read Path (로컬 읽기)

```mermaid
sequenceDiagram
    participant Client as 미국 서부 사용자
    participant R53 as Route 53
    participant USW as us-west-2 EKS
    participant Cache as ElastiCache Replica
    participant Aurora as Aurora Replica

    Client->>R53: GET /api/products/123
    Note over R53: Latency routing → us-west-2
    R53->>USW: Forward request

    USW->>Cache: Check cache
    alt Cache Hit
        Cache-->>USW: Product data
    else Cache Miss
        USW->>Aurora: Query replica
        Aurora-->>USW: Product data
        USW->>Cache: Update cache
    end

    USW-->>Client: Response (< 50ms)
```

**Read Path 특징:**
- 사용자에게 가장 가까운 리전에서 처리
- ElastiCache를 먼저 확인하여 지연시간 최소화
- Aurora/DocumentDB 로컬 복제본에서 읽기
- 평균 응답 시간: 30-50ms

### Write Path (Primary 전달)

```mermaid
sequenceDiagram
    participant Client as 미국 서부 사용자
    participant R53 as Route 53
    participant USW as us-west-2 EKS
    participant USE as us-east-1 EKS
    participant Aurora as Aurora Primary
    participant Kafka as MSK Kafka

    Client->>R53: POST /api/orders
    Note over R53: Latency routing → us-west-2
    R53->>USW: Forward request

    Note over USW: Write operation detected
    USW->>USE: Forward to primary region
    USE->>Aurora: Write to primary
    Aurora-->>USE: Write confirmed
    USE->>Kafka: Publish order-created event
    USE-->>USW: Response
    USW-->>Client: Order created (< 200ms)

    Note over Aurora: Async replication to us-west-2
```

**Write Path 특징:**
- Secondary 리전에서 받은 쓰기 요청은 Primary로 전달
- Primary에서 트랜잭션 처리 후 응답
- 이벤트는 MSK Kafka로 발행
- 데이터는 비동기로 Secondary에 복제
- 평균 응답 시간: 150-200ms

## Write Forwarding 메커니즘

### 서비스 레벨 구현

```go
// Go 서비스 예시 (Order Service)
func (h *OrderHandler) CreateOrder(c *gin.Context) {
    region := os.Getenv("AWS_REGION")
    primaryRegion := os.Getenv("PRIMARY_REGION") // "us-east-1"

    if region != primaryRegion {
        // Secondary 리전이면 Primary로 전달
        resp, err := h.forwardToPrimary(c.Request)
        if err != nil {
            c.JSON(500, gin.H{"error": "Primary region unavailable"})
            return
        }
        c.Data(resp.StatusCode, "application/json", resp.Body)
        return
    }

    // Primary 리전에서 직접 처리
    order, err := h.orderService.Create(c.Request.Context(), orderRequest)
    // ...
}
```

```java
// Java 서비스 예시 (Payment Service)
@Service
public class PaymentService {

    @Value("${aws.region}")
    private String currentRegion;

    @Value("${primary.region}")
    private String primaryRegion;

    public PaymentResponse processPayment(PaymentRequest request) {
        if (!currentRegion.equals(primaryRegion)) {
            return forwardToPrimary(request);
        }

        // Primary 리전에서 직접 처리
        return executePayment(request);
    }
}
```

### Aurora Global Database Write Forwarding

Aurora Global Database는 네이티브 Write Forwarding을 지원합니다.

```sql
-- Secondary 리전에서 실행
-- Aurora가 자동으로 Primary로 전달
INSERT INTO orders (user_id, total_amount, status)
VALUES ('user-123', 150000, 'PENDING');

-- Write Forwarding 활성화 확인
SELECT * FROM aurora_global_db_status();
```

```hcl
# Terraform 설정
resource "aws_rds_cluster" "secondary" {
  # ...
  enable_global_write_forwarding = true
}
```

## 일관성 모델

### 데이터 유형별 일관성 전략

```mermaid
flowchart TB
    subgraph Strong["Strong Consistency (강한 일관성)"]
        direction LR
        S1[주문 Order]
        S2[결제 Payment]
        S3[재고 Inventory]
        S4[계정 Account]
    end

    subgraph Eventual["Eventual Consistency (최종 일관성)"]
        direction LR
        E1[상품 카탈로그]
        E2[검색 인덱스]
        E3[추천]
        E4[리뷰]
    end

    subgraph Session["Session Consistency"]
        direction LR
        SS1[장바구니]
        SS2[위시리스트]
        SS3[사용자 세션]
    end

    Strong --> Primary[(Primary Region)]
    Eventual --> Local[(Local Region)]
    Session --> Cache[(ElastiCache)]
```

| 일관성 수준 | 적용 대상 | 이유 | 복제 지연 허용 |
|-------------|-----------|------|---------------|
| **Strong** | 주문, 결제, 재고, 계정 | 금융 트랜잭션, 중복 방지 필수 | 0 (동기) |
| **Eventual** | 상품 카탈로그, 검색, 추천, 리뷰 | 약간의 지연 허용, 읽기 성능 중시 | 1-2초 |
| **Session** | 장바구니, 위시리스트, 세션 | 사용자별 격리, 즉각적 반영 필요 | N/A (캐시) |

### Strong Consistency 구현

금융 트랜잭션은 반드시 Primary 리전에서 처리합니다.

```mermaid
sequenceDiagram
    participant Client
    participant USW as us-west-2
    participant USE as us-east-1 Primary
    participant Aurora as Aurora Primary

    Client->>USW: POST /payments
    USW->>USE: Forward to primary
    USE->>Aurora: BEGIN TRANSACTION
    USE->>Aurora: INSERT INTO payments
    USE->>Aurora: UPDATE inventory SET quantity = quantity - 1
    USE->>Aurora: COMMIT
    Aurora-->>USE: Transaction committed
    USE-->>USW: Payment confirmed
    USW-->>Client: 200 OK
```

### Eventual Consistency 구현

카탈로그, 검색 데이터는 최종 일관성으로 처리합니다.

```mermaid
sequenceDiagram
    participant Admin
    participant USE as us-east-1 Primary
    participant DocDB as DocumentDB Primary
    participant Kafka as MSK Kafka
    participant USW as us-west-2
    participant OS as OpenSearch

    Admin->>USE: PUT /products/123
    USE->>DocDB: Update product
    DocDB-->>USE: Updated
    USE->>Kafka: Publish product-updated
    USE-->>Admin: 200 OK

    Note over DocDB,USW: Async replication (~1s)
    DocDB-.->USW: Replicate to secondary

    Note over Kafka,OS: Event-driven sync
    Kafka-.->OS: Update search index
```

## Read-After-Write 일관성

사용자가 쓰기 직후 자신의 데이터를 읽을 때 일관성을 보장합니다.

```mermaid
sequenceDiagram
    participant Client
    participant USW as us-west-2
    participant USE as us-east-1

    Client->>USW: POST /orders (Create)
    USW->>USE: Forward write
    USE-->>USW: Order created (id: 12345)
    USW-->>Client: 201 Created

    Note over Client,USW: Immediate read request
    Client->>USW: GET /orders/12345

    alt Replication not complete
        USW->>USE: Forward read to primary
        USE-->>USW: Order data
    else Replication complete
        USW->>USW: Read from local replica
    end

    USW-->>Client: Order data
```

### 구현 전략

```python
# Python 서비스 예시
class OrderService:
    def get_order(self, order_id: str, user_id: str) -> Order:
        # 1. 로컬 캐시 확인
        cached = self.cache.get(f"order:{order_id}")
        if cached:
            return cached

        # 2. 최근 쓰기 여부 확인 (Session sticky)
        recent_write = self.cache.get(f"recent_write:{user_id}:{order_id}")

        if recent_write:
            # Primary에서 읽기 (강한 일관성)
            return self.read_from_primary(order_id)
        else:
            # Local replica에서 읽기 (성능 우선)
            return self.read_from_local(order_id)
```

## 리전 페일오버

### 자동 페일오버 조건

```mermaid
flowchart TB
    subgraph Monitoring["Health Monitoring"]
        R53HC[Route 53 Health Check]
        CW[CloudWatch Alarms]
        ALB[ALB Health Check]
    end

    subgraph Decision["Failover Decision"]
        Auto[자동 페일오버]
        Manual[수동 페일오버]
    end

    subgraph Action["Failover Actions"]
        DNS[DNS 가중치 변경]
        Aurora[Aurora Failover]
        DocDB[DocumentDB Promotion]
        Cache[ElastiCache Promotion]
    end

    R53HC & CW & ALB --> Decision
    Auto -->|"3회 연속 실패"| DNS
    Manual -->|"운영자 결정"| Aurora & DocDB & Cache
```

### 페일오버 시나리오

| 장애 유형 | 영향 범위 | 자동/수동 | 예상 복구 시간 |
|-----------|-----------|-----------|---------------|
| 단일 AZ 장애 | 해당 AZ 서비스 | 자동 (EKS) | 30초 |
| EKS 클러스터 장애 | 리전 서비스 | 자동 (Route 53) | 1분 |
| Aurora Primary 장애 | 쓰기 작업 | 자동 (Aurora) | 1-2분 |
| 전체 리전 장애 | 모든 서비스 | 수동 (승격 필요) | 5-10분 |

## 다음 단계

- [네트워크 아키텍처](./network) - VPC 설계 및 리전 간 연결
- [데이터 아키텍처](./data) - 데이터 스토어별 복제 전략
- [재해 복구](./disaster-recovery) - 상세 페일오버 절차

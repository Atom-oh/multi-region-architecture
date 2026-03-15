---
title: Multi-Region Design
sidebar_position: 2
---

# Multi-Region Design

Multi-Region Shopping Mall implements an Active-Active multi-region architecture based on the **Write-Primary/Read-Local** pattern. This document explains why this pattern was chosen, how it works, and the consistency model in detail.

## Region Role Assignment

| Region | Role | Responsibility |
|--------|------|----------------|
| **us-east-1** | Primary | All write operations, global data master |
| **us-west-2** | Secondary | Read operations, write forwarding, promotable on failure |

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

### Comparison: Active-Passive vs Active-Active

| Aspect | Active-Passive | Active-Active |
|--------|----------------|---------------|
| **Resource Utilization** | Secondary idle | Both regions utilized |
| **Read Latency** | Single region dependent | Processed in nearest region |
| **Failover Time** | Wait for DNS propagation (minutes) | Immediate (already serving traffic) |
| **Cost Efficiency** | Low (standby resources) | High (load balanced during normal operation) |
| **Implementation Complexity** | Low | High (data consistency management) |

### Reasons for Choosing Active-Active

1. **99.99% Availability Goal**: Service continuity even with single region failure
2. **Global User Experience**: Responses from the region closest to users
3. **Cost Optimization**: Utilizing resources in both regions during normal operation
4. **Gradual Failover**: Smooth transition since traffic is already distributed

## Write-Primary / Read-Local Pattern

### Pattern Overview

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

### Read Path (Local Read)

```mermaid
sequenceDiagram
    participant Client as US West Coast User
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

**Read Path Characteristics:**
- Processed in the region closest to the user
- ElastiCache checked first to minimize latency
- Reads from Aurora/DocumentDB local replica
- Average response time: 30-50ms

### Write Path (Forward to Primary)

```mermaid
sequenceDiagram
    participant Client as US West Coast User
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

**Write Path Characteristics:**
- Write requests received at Secondary region are forwarded to Primary
- Transaction processed at Primary, then response returned
- Events published to MSK Kafka
- Data asynchronously replicated to Secondary
- Average response time: 150-200ms

## Write Forwarding Mechanism

### Service-Level Implementation

```go
// Go service example (Order Service)
func (h *OrderHandler) CreateOrder(c *gin.Context) {
    region := os.Getenv("AWS_REGION")
    primaryRegion := os.Getenv("PRIMARY_REGION") // "us-east-1"

    if region != primaryRegion {
        // Forward to Primary if in Secondary region
        resp, err := h.forwardToPrimary(c.Request)
        if err != nil {
            c.JSON(500, gin.H{"error": "Primary region unavailable"})
            return
        }
        c.Data(resp.StatusCode, "application/json", resp.Body)
        return
    }

    // Process directly in Primary region
    order, err := h.orderService.Create(c.Request.Context(), orderRequest)
    // ...
}
```

```java
// Java service example (Payment Service)
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

        // Process directly in Primary region
        return executePayment(request);
    }
}
```

### Aurora Global Database Write Forwarding

Aurora Global Database natively supports Write Forwarding.

```sql
-- Executed in Secondary region
-- Aurora automatically forwards to Primary
INSERT INTO orders (user_id, total_amount, status)
VALUES ('user-123', 150000, 'PENDING');

-- Verify Write Forwarding is enabled
SELECT * FROM aurora_global_db_status();
```

```hcl
# Terraform configuration
resource "aws_rds_cluster" "secondary" {
  # ...
  enable_global_write_forwarding = true
}
```

## Consistency Model

### Consistency Strategy by Data Type

```mermaid
flowchart TB
    subgraph Strong["Strong Consistency"]
        direction LR
        S1[Order]
        S2[Payment]
        S3[Inventory]
        S4[Account]
    end

    subgraph Eventual["Eventual Consistency"]
        direction LR
        E1[Product Catalog]
        E2[Search Index]
        E3[Recommendations]
        E4[Reviews]
    end

    subgraph Session["Session Consistency"]
        direction LR
        SS1[Cart]
        SS2[Wishlist]
        SS3[User Session]
    end

    Strong --> Primary[(Primary Region)]
    Eventual --> Local[(Local Region)]
    Session --> Cache[(ElastiCache)]
```

| Consistency Level | Applied To | Reason | Allowed Replication Lag |
|-------------------|------------|--------|------------------------|
| **Strong** | Orders, Payments, Inventory, Accounts | Financial transactions, duplicate prevention required | 0 (synchronous) |
| **Eventual** | Product Catalog, Search, Recommendations, Reviews | Slight delay acceptable, read performance priority | 1-2 seconds |
| **Session** | Cart, Wishlist, Sessions | Per-user isolation, immediate reflection needed | N/A (cache) |

### Strong Consistency Implementation

Financial transactions must be processed in the Primary region.

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

### Eventual Consistency Implementation

Catalog and search data are processed with eventual consistency.

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

## Read-After-Write Consistency

Ensuring consistency when a user reads their own data immediately after writing.

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

### Implementation Strategy

```python
# Python service example
class OrderService:
    def get_order(self, order_id: str, user_id: str) -> Order:
        # 1. Check local cache
        cached = self.cache.get(f"order:{order_id}")
        if cached:
            return cached

        # 2. Check for recent write (Session sticky)
        recent_write = self.cache.get(f"recent_write:{user_id}:{order_id}")

        if recent_write:
            # Read from Primary (strong consistency)
            return self.read_from_primary(order_id)
        else:
            # Read from local replica (performance priority)
            return self.read_from_local(order_id)
```

## Region Failover

### Automatic Failover Conditions

```mermaid
flowchart TB
    subgraph Monitoring["Health Monitoring"]
        R53HC[Route 53 Health Check]
        CW[CloudWatch Alarms]
        ALB[ALB Health Check]
    end

    subgraph Decision["Failover Decision"]
        Auto[Automatic Failover]
        Manual[Manual Failover]
    end

    subgraph Action["Failover Actions"]
        DNS[DNS Weight Change]
        Aurora[Aurora Failover]
        DocDB[DocumentDB Promotion]
        Cache[ElastiCache Promotion]
    end

    R53HC & CW & ALB --> Decision
    Auto -->|"3 consecutive failures"| DNS
    Manual -->|"Operator decision"| Aurora & DocDB & Cache
```

### Failover Scenarios

| Failure Type | Impact Scope | Auto/Manual | Expected Recovery Time |
|--------------|--------------|-------------|----------------------|
| Single AZ failure | Services in that AZ | Automatic (EKS) | 30 seconds |
| EKS cluster failure | Regional services | Automatic (Route 53) | 1 minute |
| Aurora Primary failure | Write operations | Automatic (Aurora) | 1-2 minutes |
| Full region failure | All services | **Manual** (promotion required) | 5-10 minutes |

## Next Steps

- [Network Architecture](./network) - VPC design and cross-region connectivity
- [Data Architecture](./data) - Replication strategies by data store
- [Disaster Recovery](./disaster-recovery) - Detailed failover procedures

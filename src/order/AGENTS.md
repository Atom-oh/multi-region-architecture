<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# order/

## Purpose
Java Spring Boot order processing service managing order lifecycle from creation to completion. Uses saga pattern for distributed transactions across payment, inventory, and shipping.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven dependencies |
| `Dockerfile` | Container build definition |
| `src/main/java/com/mall/order/OrderApplication.java` | Spring Boot entry |
| `src/main/java/com/mall/order/controller/OrderController.java` | REST endpoints |
| `src/main/java/com/mall/order/service/OrderService.java` | Order business logic |
| `src/main/java/com/mall/order/model/Order.java` | Order JPA entity |
| `src/main/java/com/mall/order/repository/OrderRepository.java` | JPA repository |
| `src/main/java/com/mall/order/event/OrderEventPublisher.java` | Kafka publisher |
| `src/main/resources/application.yml` | Spring configuration |
| `src/main/resources/db/migration/V1__init.sql` | Flyway migration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/order/config/` | Spring configurations |
| `src/main/java/com/mall/order/controller/` | REST controllers |
| `src/main/java/com/mall/order/dto/` | Request/response DTOs |
| `src/main/java/com/mall/order/event/` | Kafka event publishing |
| `src/main/java/com/mall/order/model/` | JPA entities |
| `src/main/java/com/mall/order/repository/` | Data repositories |
| `src/main/java/com/mall/order/service/` | Business services |

## For AI Agents

### Working In This Directory
- Uses Spring Data JPA with Aurora PostgreSQL
- Order status: PENDING, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
- Publishes order.created, order.updated events to Kafka

### Common Patterns
```java
// Service with transaction
@Transactional
public Order createOrder(CreateOrderRequest request) {
    // ... order creation with saga orchestration
}
```

## Dependencies
### Internal
- `shared/java` mall-common library
### External
- Spring Boot 3.2.2
- Spring Data JPA
- Spring Kafka
- Flyway

<!-- MANUAL: -->

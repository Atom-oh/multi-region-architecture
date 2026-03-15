<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# returns/

## Purpose
Java Spring Boot returns management service handling return requests, approvals, and refund coordination. Publishes events for payment refunds and inventory restocking.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven dependencies |
| `Dockerfile` | Container build definition |
| `src/main/java/com/mall/returns/ReturnsApplication.java` | Spring Boot entry |
| `src/main/java/com/mall/returns/controller/ReturnController.java` | REST endpoints |
| `src/main/java/com/mall/returns/service/ReturnService.java` | Return logic |
| `src/main/java/com/mall/returns/model/ReturnRequest.java` | Return request entity |
| `src/main/java/com/mall/returns/model/ReturnItem.java` | Return item entity |
| `src/main/java/com/mall/returns/event/ReturnEventPublisher.java` | Kafka publisher |
| `src/main/resources/application.yml` | Spring configuration |
| `src/main/resources/db/migration/V1__init.sql` | Flyway migration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/returns/controller/` | REST controllers |
| `src/main/java/com/mall/returns/dto/` | Request/response DTOs |
| `src/main/java/com/mall/returns/event/` | Kafka event publishing |
| `src/main/java/com/mall/returns/model/` | JPA entities |
| `src/main/java/com/mall/returns/repository/` | Data repositories |
| `src/main/java/com/mall/returns/service/` | Business services |

## For AI Agents

### Working In This Directory
- Return status: REQUESTED, APPROVED, RECEIVED, REFUNDED, REJECTED
- Validates return eligibility based on order date
- Publishes return.approved event to trigger refund

### Common Patterns
```java
// Return eligibility check
public boolean isEligibleForReturn(Order order) {
    return order.getDeliveredAt()
        .plusDays(returnWindowDays)
        .isAfter(LocalDateTime.now());
}
```

## Dependencies
### Internal
- `shared/java` mall-common library
### External
- Spring Boot 3.2.2
- Spring Data JPA
- Spring Kafka

<!-- MANUAL: -->

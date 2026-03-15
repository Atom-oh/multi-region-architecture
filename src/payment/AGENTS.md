<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# payment/

## Purpose
Java Spring Boot payment processing service handling payment creation, authorization, capture, and refunds. Integrates with order service via Kafka events.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven dependencies |
| `Dockerfile` | Container build definition |
| `src/main/java/com/mall/payment/PaymentApplication.java` | Spring Boot entry |
| `src/main/java/com/mall/payment/controller/PaymentController.java` | REST endpoints |
| `src/main/java/com/mall/payment/service/PaymentService.java` | Payment logic |
| `src/main/java/com/mall/payment/model/Payment.java` | Payment JPA entity |
| `src/main/java/com/mall/payment/repository/PaymentRepository.java` | JPA repository |
| `src/main/java/com/mall/payment/event/PaymentEventPublisher.java` | Kafka publisher |
| `src/main/resources/application.yml` | Spring configuration |
| `src/main/resources/db/migration/V1__init.sql` | Flyway migration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/payment/config/` | Spring configurations |
| `src/main/java/com/mall/payment/controller/` | REST controllers |
| `src/main/java/com/mall/payment/dto/` | Request/response DTOs |
| `src/main/java/com/mall/payment/event/` | Kafka event publishing |
| `src/main/java/com/mall/payment/model/` | JPA entities |
| `src/main/java/com/mall/payment/repository/` | Data repositories |
| `src/main/java/com/mall/payment/service/` | Business services |

## For AI Agents

### Working In This Directory
- Payment status: PENDING, AUTHORIZED, CAPTURED, REFUNDED, FAILED
- Supports idempotent payment processing
- Publishes payment.completed, payment.failed events

### Common Patterns
```java
// Idempotent payment processing
@Transactional
public Payment processPayment(String orderId, BigDecimal amount) {
    return paymentRepository.findByOrderId(orderId)
        .orElseGet(() -> createNewPayment(orderId, amount));
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

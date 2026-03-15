<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# warehouse/

## Purpose
Java Spring Boot warehouse management service handling inventory allocation, warehouse locations, and fulfillment coordination. Consumes order events to trigger allocation.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven dependencies |
| `Dockerfile` | Container build definition |
| `src/main/java/com/mall/warehouse/WarehouseApplication.java` | Spring Boot entry |
| `src/main/java/com/mall/warehouse/controller/WarehouseController.java` | REST endpoints |
| `src/main/java/com/mall/warehouse/service/WarehouseService.java` | Warehouse logic |
| `src/main/java/com/mall/warehouse/model/Warehouse.java` | Warehouse entity |
| `src/main/java/com/mall/warehouse/model/Allocation.java` | Allocation entity |
| `src/main/java/com/mall/warehouse/event/OrderEventConsumer.java` | Kafka consumer |
| `src/main/resources/application.yml` | Spring configuration |
| `src/main/resources/db/migration/V1__init.sql` | Flyway migration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/warehouse/controller/` | REST controllers |
| `src/main/java/com/mall/warehouse/dto/` | Request/response DTOs |
| `src/main/java/com/mall/warehouse/event/` | Kafka consumers |
| `src/main/java/com/mall/warehouse/model/` | JPA entities |
| `src/main/java/com/mall/warehouse/repository/` | Data repositories |
| `src/main/java/com/mall/warehouse/service/` | Business services |

## For AI Agents

### Working In This Directory
- Allocation status: PENDING, ALLOCATED, PICKED, SHIPPED
- Selects nearest warehouse based on region
- Consumes order.created events for auto-allocation

### Common Patterns
```java
// Region-aware warehouse selection
public Warehouse selectWarehouse(String region, List<OrderItem> items) {
    return warehouseRepository.findByRegionWithStock(region, items);
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

<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# pricing/

## Purpose
Java Spring Boot dynamic pricing service managing pricing rules, promotions, discounts, and real-time price calculations. Supports tiered pricing and time-based promotions.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven dependencies |
| `Dockerfile` | Container build definition |
| `src/main/java/com/mall/pricing/PricingApplication.java` | Spring Boot entry |
| `src/main/java/com/mall/pricing/controller/PricingController.java` | REST endpoints |
| `src/main/java/com/mall/pricing/service/PricingService.java` | Pricing logic |
| `src/main/java/com/mall/pricing/model/PricingRule.java` | Pricing rule entity |
| `src/main/java/com/mall/pricing/model/Promotion.java` | Promotion entity |
| `src/main/java/com/mall/pricing/repository/PricingRuleRepository.java` | Rule repository |
| `src/main/java/com/mall/pricing/repository/PromotionRepository.java` | Promotion repository |
| `src/main/resources/application.yml` | Spring configuration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/pricing/controller/` | REST controllers |
| `src/main/java/com/mall/pricing/dto/` | Request/response DTOs |
| `src/main/java/com/mall/pricing/model/` | JPA entities |
| `src/main/java/com/mall/pricing/repository/` | Data repositories |
| `src/main/java/com/mall/pricing/service/` | Business services |

## For AI Agents

### Working In This Directory
- Pricing rules evaluated in priority order
- Promotions have start/end dates and usage limits
- Caches calculated prices in Valkey

### Common Patterns
```java
// Price calculation with rules
public BigDecimal calculatePrice(String productId, int quantity, String userId) {
    BigDecimal basePrice = getBasePrice(productId);
    return applyRules(basePrice, quantity, userId);
}
```

## Dependencies
### Internal
- `shared/java` mall-common library
### External
- Spring Boot 3.2.2
- Spring Data JPA

<!-- MANUAL: -->

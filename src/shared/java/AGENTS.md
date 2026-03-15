<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# shared/java/

## Purpose
Java mall-common library providing shared Spring Boot configurations, health checks, saga orchestration, and region-aware routing for the 7 Java microservices.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven POM with Spring Boot 3.2.2 |
| `src/main/resources/application.yml` | Default configuration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/common/config/` | Spring configurations |
| `src/main/java/com/mall/common/health/` | Health check controller |
| `src/main/java/com/mall/common/repository/` | Base repository interfaces |
| `src/main/java/com/mall/common/saga/` | Saga orchestration pattern |

## For AI Agents

### Working In This Directory
- Follow Spring Boot conventions
- Use constructor injection over field injection
- Configurations are auto-imported via Spring Boot starter

### Common Patterns
```java
// Region filter pattern
@Component
public class RegionWriteFilter implements Filter

// Saga orchestration
@Service
public class SagaOrchestrator
```

### Key Configuration Classes
| Class | Purpose |
|-------|---------|
| `AuroraConfig` | Aurora datasource setup |
| `KafkaConfig` | Kafka producer/consumer beans |
| `OtelConfig` | OpenTelemetry instrumentation |
| `RegionConfig` | Region detection |
| `RegionWriteFilter` | Write routing by region |
| `ValkeyConfig` | Valkey/Redis cache setup |

## Dependencies
### Internal
- Used by: order, payment, user-account, warehouse, returns, pricing, seller
### External
- Spring Boot 3.2.2
- Spring Data JPA
- Spring Kafka
- OpenTelemetry Java Agent

<!-- MANUAL: -->

<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# shared/go/

## Purpose
Go shared packages providing common functionality for the 5 Go microservices: api-gateway, event-bus, cart, search, and inventory.

## Key Files
| File | Description |
|------|-------------|
| `go.mod` | Module definition with dependencies |
| `pkg/tracing/tracing.go` | OpenTelemetry tracer setup |
| `pkg/health/health.go` | Health check utilities |
| `pkg/kafka/producer.go` | Kafka producer wrapper |
| `pkg/kafka/consumer.go` | Kafka consumer wrapper |
| `pkg/valkey/client.go` | Valkey (Redis) client |
| `pkg/aurora/client.go` | Aurora PostgreSQL client |
| `pkg/config/config.go` | Environment config loader |
| `pkg/region/middleware.go` | Region-aware Gin middleware |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `pkg/tracing/` | OpenTelemetry tracing setup |
| `pkg/health/` | Health check handlers |
| `pkg/kafka/` | Kafka producer and consumer |
| `pkg/valkey/` | Valkey cache client |
| `pkg/aurora/` | Aurora database client |
| `pkg/config/` | Configuration management |
| `pkg/region/` | Region detection middleware |

## For AI Agents

### Working In This Directory
- Follow Go idioms: short variable names, error handling
- Use zap logger for structured logging
- All clients should support graceful shutdown

### Common Patterns
```go
// Region middleware pattern
func RegionMiddleware() gin.HandlerFunc
// Health check pattern
func NewHealthHandler(checks ...HealthCheck) *Handler
```

## Dependencies
### Internal
- Used by: api-gateway, event-bus, cart, search, inventory
### External
- go.opentelemetry.io/otel
- github.com/gin-gonic/gin
- github.com/segmentio/kafka-go
- github.com/redis/go-redis/v9
- github.com/jackc/pgx/v5

<!-- MANUAL: -->

<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# event-bus/

## Purpose
Go-based event distribution service that receives events via HTTP and publishes them to Kafka topics. Provides a unified event ingestion API for all services.

## Key Files
| File | Description |
|------|-------------|
| `cmd/main.go` | Application entry point |
| `go.mod` | Go module dependencies |
| `Dockerfile` | Container build definition |
| `internal/config/config.go` | Configuration loader |
| `internal/handler/events.go` | Event submission handler |
| `internal/handler/health.go` | Health check endpoint |
| `internal/model/event.go` | Event data structures |
| `internal/producer/event_producer.go` | Kafka producer |
| `internal/service/event_service.go` | Event processing logic |
| `internal/middleware/logger.go` | Request logging |
| `internal/middleware/region.go` | Region context |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `cmd/` | Main application entry |
| `internal/config/` | Configuration |
| `internal/handler/` | HTTP handlers |
| `internal/middleware/` | Gin middleware |
| `internal/model/` | Data models |
| `internal/producer/` | Kafka producer |
| `internal/service/` | Business logic |

## For AI Agents

### Working In This Directory
- Events are published to topic based on event type
- Region metadata is attached to all events
- Uses async Kafka producer for throughput

### Common Patterns
```go
// Event structure
type Event struct {
    Type      string
    Payload   json.RawMessage
    Region    string
    Timestamp time.Time
}
```

## Dependencies
### Internal
- `shared/go/pkg/kafka` for Kafka producer
- `shared/go/pkg/tracing` for distributed tracing
### External
- github.com/segmentio/kafka-go

<!-- MANUAL: -->

<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# inventory/

## Purpose
Go-based inventory management service using Aurora PostgreSQL for stock tracking. Supports stock queries, reservations, and inventory events for downstream services.

## Key Files
| File | Description |
|------|-------------|
| `cmd/main.go` | Application entry point |
| `go.mod` | Go module dependencies |
| `Dockerfile` | Container build definition |
| `migrations/V1__init.sql` | Database schema |
| `internal/config/config.go` | Configuration loader |
| `internal/handler/inventory.go` | Inventory handlers |
| `internal/handler/health.go` | Health check endpoint |
| `internal/model/inventory.go` | Inventory models |
| `internal/repository/inventory_repo.go` | Aurora repository |
| `internal/service/inventory_service.go` | Business logic |
| `internal/producer/inventory_producer.go` | Kafka event producer |
| `internal/middleware/region.go` | Region middleware |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `cmd/` | Main application entry |
| `internal/config/` | Configuration |
| `internal/handler/` | HTTP handlers |
| `internal/middleware/` | Gin middleware |
| `internal/model/` | Data models |
| `internal/repository/` | Aurora PostgreSQL |
| `internal/service/` | Business logic |
| `internal/producer/` | Kafka producer |
| `migrations/` | Flyway migrations |

## For AI Agents

### Working In This Directory
- Uses Aurora PostgreSQL with read replicas
- Stock reservations use database transactions
- Publishes inventory.updated events on changes

### Common Patterns
```go
// Reservation pattern with transaction
func (r *Repo) ReserveStock(ctx, productID string, qty int) error {
    tx, _ := r.db.BeginTx(ctx, nil)
    defer tx.Rollback()
    // ... reservation logic
    return tx.Commit()
}
```

## Dependencies
### Internal
- `shared/go/pkg/aurora` for PostgreSQL client
- `shared/go/pkg/kafka` for event publishing
### External
- github.com/jackc/pgx/v5

<!-- MANUAL: -->

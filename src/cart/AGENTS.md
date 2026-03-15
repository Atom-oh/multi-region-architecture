<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# cart/

## Purpose
Go-based shopping cart service using Valkey (Redis) for fast cart storage and retrieval. Supports add, update, remove items and cart expiration.

## Key Files
| File | Description |
|------|-------------|
| `cmd/main.go` | Application entry point |
| `go.mod` | Go module dependencies |
| `Dockerfile` | Container build definition |
| `internal/config/config.go` | Configuration loader |
| `internal/handler/cart.go` | Cart CRUD handlers |
| `internal/handler/health.go` | Health check endpoint |
| `internal/model/cart.go` | Cart and item models |
| `internal/repository/cart_repo.go` | Valkey cart storage |
| `internal/service/cart_service.go` | Cart business logic |
| `internal/middleware/region.go` | Region middleware |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `cmd/` | Main application entry |
| `internal/config/` | Configuration |
| `internal/handler/` | HTTP handlers |
| `internal/middleware/` | Gin middleware |
| `internal/model/` | Data models |
| `internal/repository/` | Valkey storage |
| `internal/service/` | Business logic |

## For AI Agents

### Working In This Directory
- Carts are stored in Valkey with TTL expiration
- Cart key format: `cart:{userId}`
- Items stored as JSON in hash fields

### Common Patterns
```go
// Cart storage pattern
type CartRepository interface {
    GetCart(ctx, userID string) (*Cart, error)
    SaveCart(ctx, cart *Cart) error
    DeleteCart(ctx, userID string) error
}
```

## Dependencies
### Internal
- `shared/go/pkg/valkey` for Redis client
- `shared/go/pkg/tracing` for distributed tracing
### External
- github.com/redis/go-redis/v9

<!-- MANUAL: -->

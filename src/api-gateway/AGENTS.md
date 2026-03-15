<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# api-gateway/

## Purpose
Go-based API gateway service providing routing, rate limiting, and request proxying to downstream microservices. Acts as the single entry point for all client requests.

## Key Files
| File | Description |
|------|-------------|
| `cmd/main.go` | Application entry point |
| `go.mod` | Go module dependencies |
| `Dockerfile` | Container build definition |
| `internal/config/config.go` | Configuration loader |
| `internal/routes/routes.go` | Route definitions |
| `internal/handler/proxy.go` | Reverse proxy handler |
| `internal/handler/health.go` | Health check endpoint |
| `internal/middleware/ratelimit.go` | Rate limiting middleware |
| `internal/middleware/logger.go` | Request logging |
| `internal/middleware/region.go` | Region header injection |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `cmd/` | Main application entry |
| `internal/config/` | Configuration management |
| `internal/handler/` | HTTP handlers |
| `internal/middleware/` | Gin middleware |
| `internal/routes/` | Route registration |

## For AI Agents

### Working In This Directory
- Uses Gin framework for HTTP routing
- Rate limiting uses Valkey for distributed state
- All requests are proxied to internal services

### Common Patterns
```go
// Middleware chain
router.Use(middleware.Logger(), middleware.Region(), middleware.RateLimit())
// Proxy pattern
proxy.ServeHTTP(c.Writer, c.Request)
```

## Dependencies
### Internal
- `shared/go/pkg/` for tracing, health, config, region
### External
- github.com/gin-gonic/gin
- go.uber.org/zap

<!-- MANUAL: -->

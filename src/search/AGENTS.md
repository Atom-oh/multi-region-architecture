<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# search/

## Purpose
Go-based product search service using OpenSearch for full-text search, faceted filtering, and relevance ranking. Consumes catalog events to keep index synchronized.

## Key Files
| File | Description |
|------|-------------|
| `cmd/main.go` | Application entry point |
| `go.mod` | Go module dependencies |
| `Dockerfile` | Container build definition |
| `internal/config/config.go` | Configuration loader |
| `internal/handler/search.go` | Search query handler |
| `internal/handler/health.go` | Health check endpoint |
| `internal/repository/opensearch.go` | OpenSearch client |
| `internal/service/search_service.go` | Search logic |
| `internal/consumer/catalog_consumer.go` | Kafka catalog event consumer |
| `internal/middleware/region.go` | Region middleware |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `cmd/` | Main application entry |
| `internal/config/` | Configuration |
| `internal/handler/` | HTTP handlers |
| `internal/middleware/` | Gin middleware |
| `internal/repository/` | OpenSearch client |
| `internal/service/` | Business logic |
| `internal/consumer/` | Kafka consumers |

## For AI Agents

### Working In This Directory
- Index name: `products`
- Supports query, filters, pagination, sorting
- Catalog consumer updates index on product changes

### Common Patterns
```go
// Search request pattern
type SearchRequest struct {
    Query    string
    Filters  map[string]interface{}
    Page     int
    PageSize int
    Sort     string
}
```

## Dependencies
### Internal
- `shared/go/pkg/kafka` for event consumption
- `shared/go/pkg/tracing` for distributed tracing
### External
- github.com/opensearch-project/opensearch-go/v2

<!-- MANUAL: -->

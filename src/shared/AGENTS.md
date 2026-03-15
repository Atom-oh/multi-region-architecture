<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# shared/

## Purpose
Cross-language shared libraries providing common functionality for tracing, health checks, database clients, caching, messaging, and region-aware routing across all microservices.

## Key Files
| File | Description |
|------|-------------|
| `go/go.mod` | Go module definition |
| `java/pom.xml` | Maven POM for Java library |
| `python/requirements.txt` | Python dependencies |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `go/` | Go shared packages for 5 Go services |
| `java/` | Java mall-common library for 7 Java services |
| `python/` | Python mall_common package for 8 Python services |

## For AI Agents

### Working In This Directory
- Changes here affect multiple services - test thoroughly
- Each language has its own patterns; match existing style
- OpenTelemetry tracing is instrumented in all libraries

### Common Patterns
- Region detection from environment/headers
- Connection pooling for databases and caches
- Graceful shutdown handling
- Health check aggregation

## Dependencies
### Internal
- Used by all 20 microservices
### External
- OpenTelemetry SDK (all languages)
- AWS SDK (Aurora, DocumentDB, Valkey, S3)
- Kafka client libraries

<!-- MANUAL: -->

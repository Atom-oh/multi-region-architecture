<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# src/

## Purpose
Root directory for all microservices in the multi-region e-commerce platform. Contains 20 microservices across 3 languages (Go, Java, Python) plus shared libraries for cross-cutting concerns.

## Key Files
| File | Description |
|------|-------------|
| `shared/` | Cross-language shared libraries |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `shared/` | Shared libraries (Go, Java, Python) |
| `api-gateway/` | Go - API routing and rate limiting |
| `event-bus/` | Go - Kafka event distribution |
| `cart/` | Go - Shopping cart with Valkey cache |
| `search/` | Go - OpenSearch product search |
| `inventory/` | Go - Stock management with Aurora |
| `order/` | Java - Order processing with saga |
| `payment/` | Java - Payment processing |
| `user-account/` | Java - Auth and session management |
| `warehouse/` | Java - Warehouse allocation |
| `returns/` | Java - Return request handling |
| `pricing/` | Java - Dynamic pricing and promotions |
| `seller/` | Java - Seller portal with S3 |
| `product-catalog/` | Python - Product CRUD with DocumentDB |
| `shipping/` | Python - Shipment tracking |
| `user-profile/` | Python - User preferences |
| `recommendation/` | Python - ML recommendations |
| `wishlist/` | Python - Wishlist with Valkey |
| `analytics/` | Python - Event analytics with S3 |
| `notification/` | Python - Multi-channel notifications |
| `review/` | Python - Product reviews |

## For AI Agents

### Working In This Directory
- Go services use `cmd/main.go` entry and `internal/` packages
- Java services use Spring Boot with `src/main/java/com/mall/{service}/`
- Python services use FastAPI with `app/main.py` entry
- All services have OpenTelemetry tracing instrumented

### Common Patterns
- Region-aware routing via middleware
- Kafka for async event communication
- Health endpoints at `/health` and `/health/ready`

## Dependencies
### Internal
- All services depend on `shared/` libraries for their language
### External
- Go: Gin, zap, segmentio/kafka-go, redis/go-redis
- Java: Spring Boot 3.2.2, Spring Data JPA, Spring Kafka
- Python: FastAPI, uvicorn, aiokafka, motor

<!-- MANUAL: -->

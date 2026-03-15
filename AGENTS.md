<!-- Generated: 2026-03-15 | Updated: 2026-03-15 -->

# Multi-Region Shopping Mall Architecture

## Purpose
Production-grade multi-region e-commerce platform deployed across AWS us-east-1 (primary) and us-west-2 (secondary). 20 microservices across 3 language stacks with full observability, managed via Terraform and Kubernetes.

## Architecture Overview
- **Active-Active** multi-region with primary write region and read replicas
- **20 Microservices**: 5 Go/Gin, 7 Java/Spring Boot, 8 Python/FastAPI
- **Data Layer**: Aurora Global, DocumentDB Global, ElastiCache Global, MSK, OpenSearch
- **Observability**: OpenTelemetry → OTEL Collector → AWS X-Ray + Tempo + Prometheus + CloudWatch
- **Edge**: CloudFront + WAF + Route 53 (latency-based routing)

## Key Files

| File | Description |
|------|-------------|
| `CLAUDE.md` | AI assistant instructions and project conventions |
| `AGENTS.md` | This file — root of hierarchical AI documentation |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `src/` | All 20 microservice source code + shared libraries (see `src/AGENTS.md`) |
| `k8s/` | Kubernetes manifests — base, services, overlays, infra (see `k8s/AGENTS.md`) |
| `terraform/` | AWS infrastructure as code — modules, environments, global (see `terraform/AGENTS.md`) |
| `scripts/` | Build, deployment, and seed data scripts (see `scripts/AGENTS.md`) |
| `docs/` | Architecture documentation and diagrams |
| `.github/` | CI/CD workflows |

## For AI Agents

### Service Categories

| Category | Services | Language |
|----------|----------|----------|
| **Core** | api-gateway, order, payment, product-catalog, cart, search, inventory | Go + Java + Python |
| **User** | user-account, user-profile, review, wishlist | Java + Python |
| **Fulfillment** | shipping, warehouse, returns | Python + Java |
| **Business** | pricing, seller, recommendation, notification | Java + Python |
| **Platform** | event-bus, analytics | Go + Python |

### Language Patterns

| Stack | Framework | Shared Lib | Build |
|-------|-----------|-----------|-------|
| Go | Gin + zap | `src/shared/go/` | Docker multi-stage, `go mod tidy` in build |
| Java | Spring Boot 3.2.2 | `src/shared/java/` (mall-common) | Maven + OTEL Java Agent (`-javaagent`) |
| Python | FastAPI + uvicorn | `src/shared/python/mall_common/` | pip + Docker multi-stage |

### Tracing
All services are instrumented with OpenTelemetry. Traces flow: Service SDK → OTEL Collector DaemonSet → AWS X-Ray + Grafana Tempo. W3C traceparent propagation via HTTP headers and Kafka message headers.

### Working In This Repository
- Run `scripts/build-and-push.sh` to build and push all service images to ECR
- Kustomize overlays per region: `k8s/overlays/us-east-1/` and `k8s/overlays/us-west-2/`
- ArgoCD ApplicationSets auto-deploy from `k8s/infra/argocd/apps/`
- Terraform state is remote (S3 + DynamoDB locking)

### Testing Requirements
- Go: `go test ./...` in each service directory
- Java: `mvn test` in each service directory
- Python: `pytest` in each service directory
- Infrastructure: `terraform plan` in each environment

<!-- MANUAL: -->

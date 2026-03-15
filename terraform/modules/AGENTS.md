<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Terraform Modules

## Purpose
Reusable infrastructure modules organized by AWS service category. Each module encapsulates a single resource or tightly-coupled resource group.

## Key Subdirectories
- `networking/` — VPC, transit-gateway, security-groups
- `compute/` — EKS cluster, ALB (Application Load Balancer)
- `data/` — Aurora-global, DocumentDB-global, ElastiCache-global, MSK, OpenSearch, S3
- `edge/` — CloudFront, Route53, WAF
- `observability/` — CloudWatch, X-Ray, Tempo-storage
- `security/` — IAM, KMS, Secrets Manager

## For AI Agents
### Working In This Directory
- **Module structure**: Every module must have `main.tf`, `variables.tf`, `outputs.tf`.
- **No hardcoded values**: All configurable values go in `variables.tf` with sensible defaults.
- **Output what consumers need**: Expose IDs, ARNs, and endpoints that other modules reference.
- **Use data sources**: Prefer `data` blocks over hardcoded ARNs for cross-module references.
- **Naming convention**: Resource names follow `${var.environment}-${var.region}-<resource>` pattern.
- **Tagging**: All resources must include Environment, Region, ManagedBy tags.

### Module Categories
| Category | Purpose |
|----------|---------|
| networking | Network foundation (VPC, subnets, routing, connectivity) |
| compute | Container orchestration and load balancing |
| data | Databases, caches, message queues, storage |
| edge | CDN, DNS, web application firewall |
| observability | Logging, tracing, metrics |
| security | Identity, encryption, secrets |

<!-- MANUAL: -->

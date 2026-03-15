<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Service Manifests

## Purpose
Kubernetes Deployment and Service manifests for all shopping mall microservices, organized by business domain.

## Key Files
| File | Description |
|------|-------------|
| `kustomization.yaml` | Aggregates all service categories |

## Subdirectories
| Directory | Services |
|-----------|----------|
| `core/` | product-catalog, search, cart, order, payment, inventory |
| `user/` | user-account, user-profile, wishlist, review |
| `fulfillment/` | shipping, warehouse, returns |
| `business/` | pricing, recommendation, notification, seller |
| `platform/` | api-gateway, event-bus, analytics |

## Service Structure
Each service directory contains:
- `deployment.yaml` — Deployment with container spec, probes, resource requests
- `.gitkeep` — Placeholder for future Service manifests

## For AI Agents
### Working In This Directory
- Each service deploys to its category namespace (e.g., `core-services`, `user-services`)
- Deployments reference container images from ECR
- Resource requests/limits should match quota in `base/resource-quotas/`
- Common label: `app.kubernetes.io/part-of: shopping-mall`
- Environment variables injected via Kustomize overlays (not hardcoded here)
- Each category has its own `kustomization.yaml` aggregating services

### Adding a New Service
1. Create directory under appropriate category
2. Add `deployment.yaml` with standard labels and probes
3. Update category's `kustomization.yaml` to include new service
4. Verify resource requests fit within namespace quota

<!-- MANUAL: -->

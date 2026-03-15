<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Kubernetes Manifests

## Purpose
Multi-region Kubernetes deployment configuration for a shopping mall e-commerce platform. Uses Kustomize for overlay-based configuration and ArgoCD for GitOps deployment.

## Key Files
| File | Description |
|------|-------------|
| (none at root) | All manifests organized in subdirectories |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `base/` | Shared resources: namespaces, network policies, resource quotas |
| `services/` | Application deployments grouped by domain (core, user, fulfillment, business, platform) |
| `overlays/` | Region-specific Kustomize overlays (us-east-1, us-west-2) |
| `infra/` | Infrastructure: ArgoCD, OTEL, Prometheus, Fluent Bit, Karpenter, External Secrets |

## For AI Agents
### Working In This Directory
- Use Kustomize patterns: base resources + overlays for environment variation
- Regional overlays inject: `REGION_ROLE`, `AWS_REGION`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_RESOURCE_ATTRIBUTES`
- ArgoCD ApplicationSets in `infra/argocd/apps/` auto-deploy per region
- us-east-1 is PRIMARY region, us-west-2 is SECONDARY
- All services use common label `app.kubernetes.io/part-of: shopping-mall`

### Deployment Flow
1. Base manifests define shared policies and quotas
2. Services define Deployment + Service per microservice
3. Overlays patch deployments with region-specific config
4. ArgoCD ApplicationSets sync overlays to target clusters

<!-- MANUAL: -->

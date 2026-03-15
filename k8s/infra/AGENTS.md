<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Infrastructure Components

## Purpose
Platform infrastructure deployed alongside application services: GitOps (ArgoCD), observability (OTEL, Prometheus, Tempo, Fluent Bit), autoscaling (Karpenter), and secrets management.

## Key Files
| File | Description |
|------|-------------|
| (none at root) | Components organized in subdirectories |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `argocd/` | ArgoCD HA install + ApplicationSets for GitOps |
| `otel-collector/` | OpenTelemetry Collector for trace/metric collection |
| `prometheus-stack/` | Prometheus + Grafana via kube-prometheus-stack |
| `tempo/` | Grafana Tempo for distributed tracing storage |
| `fluent-bit/` | Log forwarding to CloudWatch/S3 |
| `karpenter/` | Node autoscaling with NodePools and EC2NodeClass |
| `external-secrets/` | External Secrets Operator for AWS Secrets Manager |

## ArgoCD ApplicationSets
| File | Target |
|------|--------|
| `argocd/apps/appset-core.yaml` | Core services per region |
| `argocd/apps/appset-user.yaml` | User services per region |
| `argocd/apps/appset-fulfillment.yaml` | Fulfillment services per region |
| `argocd/apps/appset-business.yaml` | Business services per region |
| `argocd/apps/appset-platform.yaml` | Platform services per region |
| `argocd/apps/root-app.yaml` | Root application for app-of-apps |

## For AI Agents
### Working In This Directory
- ArgoCD ApplicationSets use cluster generator with `region` label selector
- OTEL Collector receives traces at `otel-collector.platform.svc.cluster.local:4317`
- Karpenter NodePools: `general` (spot instances), `critical` (on-demand)
- External Secrets syncs from AWS Secrets Manager via ClusterSecretStore
- Prometheus installed via Helm values in `prometheus-stack/values.yaml`
- Each component has its own namespace (argocd, observability, fluent-bit, external-secrets)

<!-- MANUAL: -->

<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Infrastructure Components

## Purpose
Platform infrastructure deployed alongside application services: GitOps (ArgoCD), observability (OTel Collector, ClickHouse, Prometheus, Tempo, Grafana), autoscaling (Karpenter, KEDA), secrets management, and CI/CD runners.

## Key Files
| File | Description |
|------|-------------|
| (none at root) | Components organized in subdirectories |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `argocd/` | ArgoCD HA install + ApplicationSets for US clusters |
| `argocd-korea/` | ArgoCD ApplicationSets for Korea clusters (managed from mgmt) |
| `otel-collector/` | OpenTelemetry Collector for trace/log/metric collection |
| `clickhouse/` | ClickHouse for trace/log analytics storage |
| `clickhouse-mgmt/` | ClickHouse config for Korea mgmt cluster |
| `prometheus-stack/` | Prometheus + Grafana via kube-prometheus-stack |
| `grafana/` | Grafana dashboards and datasource configs |
| `grafana-korea-nlb/` | Korea Grafana NLB (internal, CloudFront-only access) |
| `tempo/` | Grafana Tempo for distributed tracing (US primary) |
| `tempo-west/` | Grafana Tempo for US-West region |
| `karpenter/` | Node autoscaling (US clusters) |
| `karpenter-apne2-mgmt/` | Karpenter for Korea mgmt cluster |
| `karpenter-apne2-az-a/` | Karpenter for Korea AZ-A cluster |
| `karpenter-apne2-az-c/` | Karpenter for Korea AZ-C cluster |
| `external-secrets/` | External Secrets Operator for AWS Secrets Manager |
| `keda/` | KEDA event-driven autoscaling |
| `actions-runner/` | GitHub Actions self-hosted runners (ARC v2, x86 + arm64) |
| `storageclass/` | Storage class definitions (gp3) |

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
- Each component has its own namespace (argocd, observability, platform, external-secrets, keda, actions-runner-system)

<!-- MANUAL: -->

<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Regional Overlays

## Purpose
Kustomize overlays that patch base manifests with region-specific configuration. Enables multi-region deployment from a single source with environment-specific values.

## Key Files
| File | Description |
|------|-------------|
| `us-east-1/kustomization.yaml` | Primary region overlay (full stack) |
| `us-west-2/kustomization.yaml` | Secondary region overlay (full stack) |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `us-east-1/` | Primary region (us-east-1) configuration |
| `us-west-2/` | Secondary region (us-west-2) configuration |
| `{region}/core/` | Core services overlay for ArgoCD ApplicationSet |
| `{region}/user/` | User services overlay |
| `{region}/fulfillment/` | Fulfillment services overlay |
| `{region}/business/` | Business services overlay |
| `{region}/platform/` | Platform services overlay |

## Environment Variables Injected
| Variable | Description |
|----------|-------------|
| `REGION_ROLE` | PRIMARY or SECONDARY |
| `AWS_REGION` | us-east-1 or us-west-2 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Regional OTEL collector endpoint |
| `OTEL_RESOURCE_ATTRIBUTES` | Trace attributes with region metadata |

## ConfigMap Data (region-config)
- `AURORA_ENDPOINT` — Regional Aurora writer endpoint
- `AURORA_READER_ENDPOINT` — Aurora read replica endpoint
- `DOCUMENTDB_ENDPOINT` — DocumentDB cluster endpoint
- `VALKEY_ENDPOINT` — ElastiCache Valkey endpoint
- `MSK_BROKERS` — Kafka broker list
- `OPENSEARCH_ENDPOINT` — OpenSearch domain endpoint

## For AI Agents
### Working In This Directory
- Per-category overlays exist for ArgoCD ApplicationSet targeting
- Root overlay (`{region}/kustomization.yaml`) deploys full stack
- Patches use JSON Patch (RFC 6902) to inject env vars into all Deployments
- Labels `region` and `region-role` applied to all resources
- us-east-1 is PRIMARY (read-write), us-west-2 is SECONDARY (read-replica failover)
- Add new region by copying existing overlay and updating endpoints

<!-- MANUAL: -->

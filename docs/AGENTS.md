<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Documentation

## Purpose
Technical design documents and architecture diagrams for the multi-region shopping mall platform (us-east-1/us-west-2).

## Key Files
| File | Description |
|------|-------------|

| `deployment-design.md` | Infrastructure design, GitOps patterns, security, cost estimates |
| `deployment-execution-plan.md` | Step-by-step deployment phases (Terraform, ArgoCD, verification) |
| `argocd-gitops-design.md` | App-of-ApplicationSets pattern for multi-cluster GitOps |
| `otel-tracing-design.md` | OpenTelemetry + Grafana Tempo distributed tracing design |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `architecture/` | System architecture documentation and diagrams |
| `architecture/diagrams/` | Visual diagrams (PNG, DrawIO) |

## Architecture Files
| File | Description |
|------|-------------|
| `architecture/architecture-design.md` | Comprehensive system architecture (large file) |
| `architecture/diagrams/multi-region-architecture.png` | Multi-region infrastructure diagram |
| `architecture/diagrams/multi-region-architecture.drawio` | Editable DrawIO source |

## For AI Agents
### Working In This Directory
- Design docs are reference material; update when infrastructure changes
- `architecture-design.md` is large (~27k tokens); read in sections
- Diagrams in `architecture/diagrams/` should match doc descriptions
- Cost estimates in `deployment-design.md` need updates if instance types change

<!-- MANUAL: -->

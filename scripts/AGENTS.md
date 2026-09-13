<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 | Updated: 2026-09-13 -->

# Scripts

## Purpose
Build automation, data seeding and PR review tooling for the multi-region shopping mall platform. Includes Docker publication, database initialization and review helpers.

## Key Files
| File | Description |
|------|-------------|
| `build-and-push.sh` | Builds and pushes all 20 microservices to ECR (Go, Python, Java) |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| [pr-review/](pr-review/AGENTS.md) | PR collection, execution helpers and staged protocol; see the module guide for the operational path |
| `seed-data/` | Database seeding scripts for all data stores |
| `seed-data/k8s/` | Kubernetes Job manifests for running seeds in-cluster |

## Seed Data Scripts
| File | Target |
|------|--------|
| `seed-data/run-seed.sh` | Master orchestrator for all seed scripts |
| `seed-data/seed-aurora.sql` | Aurora PostgreSQL seed data |
| `seed-data/seed-documentdb.js` | DocumentDB (MongoDB) seed data |
| `seed-data/seed-opensearch.sh` | OpenSearch indices and mappings |
| `seed-data/seed-kafka-topics.sh` | MSK Kafka topic creation |
| `seed-data/seed-redis.sh` | ElastiCache (Valkey/Redis) seed data |

## For AI Agents
### Working In This Directory
- `build-and-push.sh` expects ECR repos to exist; uses hardcoded account ID
- Seed scripts require env vars (AURORA_ENDPOINT, DOCUMENTDB_URI, etc.)
- Run `run-seed.sh` to orchestrate all seeds; skips stores without endpoints
- K8s job at `seed-data/k8s/jobs/seed-data-job.yaml` runs seeds in-cluster

<!-- MANUAL: -->

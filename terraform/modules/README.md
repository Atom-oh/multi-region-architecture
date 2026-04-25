# Terraform Modules

Reusable modules for the multi-region shopping mall platform. Each module supports one of two deployment patterns:

- **Multi-Region** (US): us-east-1 (primary) + us-west-2 (secondary) with global data replication
- **Multi-AZ** (Korea): ap-northeast-2 with per-AZ EKS clusters and standalone data stores

## Module Classification

| Module | Category | Description |
|--------|----------|-------------|
| **Networking** | | |
| `networking/vpc` | Common | VPC with public/private/data subnets, NAT gateways |
| `networking/transit-gateway` | Multi-Region | Cross-region TGW peering (us-east-1 <-> us-west-2) |
| `networking/security-groups` | Common | Security groups for all services (EKS, ALB, NLB, data stores) |
| **Compute** | | |
| `compute/eks` | Common | EKS cluster with managed node group, Karpenter IRSA, OIDC |
| `compute/alb` | Common | AWS Load Balancer Controller IRSA role |
| `compute/nlb` | Multi-Region | Standard NLB with single target group (US regions) |
| `compute/nlb-weighted` | Multi-AZ | Weighted NLB with AZ-A/AZ-C target groups (Korea) |
| **Data** | | |
| `data/aurora-global` | Common | Aurora PostgreSQL (primary or secondary in global cluster, or standalone) |
| `data/documentdb-global` | Common | DocumentDB (primary or secondary in global cluster, or standalone) |
| `data/elasticache-global` | Common | ElastiCache Redis (primary or secondary in global datastore, or standalone) |
| `data/dsql` | Multi-Region | Aurora DSQL serverless cluster (US only) |
| `data/dsql-irsa` | Multi-Region | IRSA role for DSQL access from EKS pods |
| `data/msk` | Common | Amazon MSK (Kafka) cluster |
| `data/opensearch` | Common | OpenSearch domain with Korean analyzer |
| `data/s3` | Common | S3 buckets for static assets + analytics |
| **Edge** | | |
| `edge/cloudfront` | Primary-only | CloudFront distribution for static assets + API (us-east-1) |
| `edge/cloudfront-argocd` | Primary-only | CloudFront proxy to ArgoCD NLB (us-east-1) |
| `edge/cloudfront-grafana` | Primary-only | CloudFront proxy to Grafana NLB (us-east-1) |
| `edge/route53` | Common | Route53 latency-based routing records |
| `edge/waf` | Primary-only | WAF WebACL with AWS managed rules (us-east-1) |
| **Observability** | | |
| `observability/cloudwatch` | Common | CloudWatch dashboards and alarms |
| `observability/xray` | Common | X-Ray sampling rules and encryption |
| `observability/tempo-storage` | Common | S3 bucket + IRSA for Grafana Tempo traces |
| `observability/otel-collector-irsa` | Common | IRSA role for OTel Collector DaemonSet |
| **Security** | | |
| `security/iam` | Common | IAM roles (GitHub Actions OIDC, S3 replication, Bedrock) |
| `security/kms` | Common | KMS keys for all encrypted services |
| `security/secrets-manager` | Common | Database and service credentials |
| `security/cognito` | Primary-only | Cognito User Pool for JWT auth (us-east-1) |
| **DR** | | |
| `dr-automation` | Primary-only | Lambda failover for DocumentDB + ElastiCache (us-east-1) |

### Category Definitions

- **Common**: Used in all regions. Module behavior adapts via variables (e.g., `is_primary`).
- **Multi-Region**: Used only in US cross-region deployments (Transit Gateway, DSQL, standard NLB).
- **Multi-AZ**: Used only in Korea multi-AZ deployment (weighted NLB).
- **Primary-only**: Used only in us-east-1 (CloudFront, WAF, DR, Cognito).

## Module Interface Convention

Each module follows the standard structure:
- `main.tf` — Resource definitions
- `variables.tf` — Input variables (with `required_version >= 1.9`, `aws >= 6.0`)
- `outputs.tf` — Exported values for downstream modules

## Data Store Modes

The `aurora-global`, `documentdb-global`, and `elasticache-global` modules support two modes:

| Mode | US Primary (us-east-1) | US Secondary (us-west-2) | Korea (ap-northeast-2) |
|------|------------------------|--------------------------|------------------------|
| Global cluster | `is_primary = true` | `is_primary = false` | N/A |
| Standalone | N/A | N/A | `is_primary = true`, no `global_cluster_identifier` |

Korea's data stores are independent and do not participate in global replication.

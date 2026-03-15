# Multi-Region Shopping Mall - Deployment Design Document

## Document Information

| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | 2026-03-15 |
| Status | In Progress |
| Classification | Internal |

---

## 1. Deployment Overview

### 1.1 Target Environment

| Item | Value |
|------|-------|
| AWS Account | 180294183052 |
| IAM Role | mgmt-vpc-VSCode-Role (AdministratorAccess) |
| Domain | atomai.click |
| Route53 Zone ID | Z01703432E9KT1G1FIRFM |
| Primary Region | us-east-1 |
| Secondary Region | us-west-2 |
| Existing Infrastructure | None (clean environment) |

### 1.2 ACM Certificates

| Region | ARN | Status |
|--------|-----|--------|
| us-east-1 | arn:aws:acm:us-east-1:180294183052:certificate/f6b6907a-5747-4039-967a-a8c7c73116a7 | Issued |
| us-west-2 | arn:aws:acm:us-west-2:180294183052:certificate/18ed9116-1f33-4cfa-b922-9fde952ea169 | Issued |

### 1.3 Domain Configuration

| Subdomain | Purpose | Record Type |
|-----------|---------|-------------|
| mall.atomai.click | CloudFront (user-facing) | CNAME / Alias |
| www.mall.atomai.click | CloudFront redirect | CNAME / Alias |
| api-internal.atomai.click | ALB latency routing | Route53 Latency |

---

## 2. Infrastructure Design

### 2.1 Terraform State Management

```
┌──────────────────────────────────────────────────┐
│              Terraform State Backend              │
├──────────────────────────────────────────────────┤
│  S3 Bucket: multi-region-mall-terraform-state    │
│  DynamoDB:  multi-region-mall-terraform-locks    │
│  Region:    us-east-1                            │
│  Encryption: AES256 (SSE-S3)                     │
│  Versioning: Enabled                             │
└──────────────────────────────────────────────────┘
```

State file layout:
```
s3://multi-region-mall-terraform-state/
├── global/terraform.tfstate            # Global resources (Aurora/DocDB global clusters)
├── production/us-east-1/terraform.tfstate  # Primary region
└── production/us-west-2/terraform.tfstate  # Secondary region
```

### 2.2 Module Dependency Graph

```
                    ┌─────────┐
                    │   VPC   │
                    └────┬────┘
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
        ┌─────────┐ ┌────────┐ ┌────────┐
        │   SG    │ │  TGW   │ │  KMS   │
        └────┬────┘ └────────┘ └───┬────┘
             │                     │
    ┌────────┼────────┐     ┌──────┤
    ▼        ▼        ▼     ▼      ▼
┌──────┐ ┌──────┐ ┌──────┐ ┌──────────┐
│ EKS  │ │Aurora│ │DocDB │ │ Secrets  │
└──┬───┘ └──────┘ └──────┘ └──────────┘
   │
   ▼
┌──────┐   ┌──────┐   ┌──────┐
│ ALB  │   │ MSK  │   │  OS  │
└──────┘   └──────┘   └──────┘
   │
   ▼
┌──────────────────────────────┐
│  Route53 → CloudFront → WAF │
│  CloudWatch → X-Ray         │
└──────────────────────────────┘
```

### 2.3 Cross-Region Dependencies

| us-west-2 Resource | Depends On (from us-east-1 remote state) |
|---------------------|------------------------------------------|
| Transit Gateway Peering | `primary.outputs.transit_gateway_id` |
| ElastiCache Global | `primary.outputs.elasticache_endpoint` |
| MSK Replicator | `primary.outputs.msk_cluster_arn` |
| S3 Replication | `primary.outputs.s3_replication_role_arn` |

---

## 3. GitOps Design (ArgoCD)

### 3.1 App-of-ApplicationSets Pattern

```
                    ┌──────────────────┐
                    │   Root App       │
                    │   (App-of-Apps)  │
                    └────────┬─────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ ApplicationSet   │ │ ApplicationSet   │ │ ApplicationSet   │
│ core-services    │ │ user-services    │ │ fulfillment      │
│ (6 svc x 2 cls) │ │ (4 svc x 2 cls) │ │ (3 svc x 2 cls) │
└──────────────────┘ └──────────────────┘ └──────────────────┘
          ▼                  ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ ApplicationSet   │ │ ApplicationSet   │ │ ApplicationSet   │
│ business         │ │ platform         │ │ infra            │
│ (4 svc x 2 cls) │ │ (3 svc x 2 cls) │ │ (karpenter, etc) │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

### 3.2 ArgoCD Cluster Topology

```
┌─────────────────────────────────────────────┐
│  us-east-1 EKS (in-cluster)                │
│  ArgoCD Server (HA: 3 replicas)             │
│  ├── argocd-server                          │
│  ├── argocd-repo-server                     │
│  ├── argocd-application-controller          │
│  └── argocd-redis                           │
└─────────────────┬───────────────────────────┘
                  │ manages
                  ▼
┌─────────────────────────────────────────────┐
│  us-west-2 EKS (external cluster)          │
│  Registered via argocd cluster add          │
│  Label: region=us-west-2                    │
└─────────────────────────────────────────────┘
```

### 3.3 Kustomize Overlay Strategy

```
k8s/
├── base/                    # Shared base manifests
├── services/                # Service deployments by domain
│   ├── core/               # product-catalog, search, cart, order, payment, inventory
│   ├── user/               # user-account, user-profile, wishlist, review
│   ├── fulfillment/        # shipping, warehouse, returns
│   ├── business/           # recommendation, pricing, notification, seller
│   └── platform/           # api-gateway, event-bus, analytics
├── infra/                   # Infrastructure services
│   ├── argocd/             # ArgoCD + ApplicationSets (NEW)
│   ├── karpenter/          # Node autoscaling
│   ├── fluent-bit/         # Log shipping
│   └── external-secrets/   # Secret sync
└── overlays/
    ├── us-east-1/          # Primary: REGION_ROLE=PRIMARY + real DB endpoints
    └── us-west-2/          # Secondary: REGION_ROLE=SECONDARY + replica endpoints
```

---

## 4. Service Inventory

### 4.1 Microservices (20 total)

| Group | Services | Namespace |
|-------|----------|-----------|
| Core | product-catalog, search, cart, order, payment, inventory | core-services |
| User | user-account, user-profile, wishlist, review | user-services |
| Fulfillment | shipping, warehouse, returns | fulfillment |
| Business | recommendation, pricing, notification, seller | business-services |
| Platform | api-gateway, event-bus, analytics | platform |

### 4.2 Infrastructure Services

| Service | Purpose |
|---------|---------|
| ArgoCD | GitOps continuous delivery |
| Karpenter | Node autoscaling |
| Fluent-bit | Log aggregation to CloudWatch |
| External-secrets | AWS Secrets Manager sync |
| Prometheus Stack | Metrics (planned) |

---

## 5. Security Design

### 5.1 Encryption at Rest

| Service | KMS Key |
|---------|---------|
| Aurora PostgreSQL | `kms["aurora"]` |
| DocumentDB | `kms["documentdb"]` |
| ElastiCache (Valkey) | `kms["elasticache"]` |
| MSK (Kafka) | `kms["msk"]` |
| S3 | `kms["s3"]` |
| Terraform State | AES256 (SSE-S3) |

### 5.2 Network Security

- VPC per region with 3-tier subnets (public/private/data)
- Security groups per service (Aurora, DocDB, ElastiCache, MSK, OpenSearch)
- Transit Gateway for cross-region private connectivity
- WAF on CloudFront for edge protection
- No public access to data-tier subnets

### 5.3 Secrets Management

| Secret | Location |
|--------|----------|
| Aurora credentials | Secrets Manager (`production/aurora/credentials`) |
| DocumentDB credentials | Secrets Manager (`production/documentdb/credentials`) |
| MSK SASL/SCRAM | Secrets Manager (`production/msk/credentials`) |
| OpenSearch credentials | Secrets Manager (`production/opensearch/credentials`) |

---

## 6. Cost Estimate

### 6.1 Monthly Cost Breakdown (Pre-RI/SP)

| Category | us-east-1 | us-west-2 | Total |
|----------|-----------|-----------|-------|
| EKS (control plane + nodes) | ~$4,500 | ~$4,500 | ~$9,000 |
| Aurora Global (r6g.2xlarge writer + readers) | ~$4,200 | ~$3,800 | ~$8,000 |
| DocumentDB (r6g.2xlarge x 3) | ~$3,500 | ~$3,500 | ~$7,000 |
| ElastiCache (r7g.xlarge, 3 shards) | ~$2,800 | ~$2,800 | ~$5,600 |
| MSK (m5.2xlarge x 6 brokers) | ~$3,200 | ~$3,200 | ~$6,400 |
| OpenSearch (r6g.xlarge x 6 data) | ~$2,500 | ~$2,500 | ~$5,000 |
| CloudFront + WAF | ~$800 | - | ~$800 |
| S3 + Data Transfer | ~$600 | ~$600 | ~$1,200 |
| Other (Route53, CloudWatch, KMS) | ~$625 | ~$625 | ~$1,250 |
| **Total** | **~$22,725** | **~$21,525** | **~$44,250** |

### 6.2 Optimization Opportunities

- Reserved Instances for Aurora, DocumentDB: ~30% savings
- Savings Plans for EKS compute: ~20% savings
- ElastiCache Reserved Nodes: ~40% savings
- Estimated optimized total: ~$30,000/mo

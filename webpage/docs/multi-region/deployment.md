---
sidebar_position: 9
title: Deployment & GitOps
description: ArgoCD ApplicationSets, Terraform 구조, CI/CD
---

# Deployment & GitOps

## ArgoCD ApplicationSets

21개의 ApplicationSet이 두 리전의 K8s 리소스를 관리합니다.

### Service Domains (5)

| AppSet | 대상 |
|--------|------|
| `appset-core.yaml` | Core 서비스 (product-catalog, inventory, cart, search) |
| `appset-user.yaml` | User 서비스 (user-account, user-profile, review, wishlist) |
| `appset-fulfillment.yaml` | Fulfillment 서비스 (order, payment, shipping, returns) |
| `appset-business.yaml` | Business 서비스 (notification, recommendation, analytics, seller) |
| `appset-platform.yaml` | Platform 서비스 (api-gateway, event-bus, pricing, warehouse) |

### Infrastructure (16)

| AppSet | 대상 |
|--------|------|
| `appset-infra.yaml` | Karpenter CRDs, 기본 인프라 |
| `appset-tempo.yaml` | Tempo 배포 |
| `appset-storageclass.yaml` | gp3 StorageClass |
| `appset-helm-karpenter.yaml` | Karpenter Helm chart |
| `appset-helm-prometheus.yaml` | Prometheus stack (us-east-1) |
| `appset-helm-prometheus-west.yaml` | Prometheus stack (us-west-2) |
| `appset-helm-prometheus-korea.yaml` | Prometheus stack (ap-northeast-2) |
| `appset-helm-otel-collector.yaml` | OTel Collector Helm chart |
| `appset-helm-alb-controller.yaml` | AWS ALB Controller |
| `appset-helm-external-secrets.yaml` | External Secrets Operator |
| `appset-helm-clickhouse-operator.yaml` | ClickHouse Operator |
| `appset-clickhouse.yaml` | ClickHouse Installation |
| `appset-grafana-nlb.yaml` | Grafana NLB |
| `appset-prometheus-west-nlb.yaml` | Prometheus West NLB |
| `appset-tempo-west-nlb.yaml` | Tempo West NLB |

## Terraform Module Structure

```
terraform/
├── environments/production/
│   ├── us-east-1/main.tf        # Primary region (~260 resources)
│   └── us-west-2/main.tf        # Secondary region (~260 resources)
│
├── modules/
│   ├── networking/               # vpc, security-groups, transit-gateway
│   ├── compute/                  # eks, alb, nlb
│   ├── data/                     # aurora-global, documentdb-global, elasticache-global,
│   │                             # msk, opensearch, s3, dsql, dsql-irsa
│   ├── edge/                     # cloudfront, cloudfront-argocd, cloudfront-grafana,
│   │                             # waf, route53
│   ├── security/                 # kms, secrets-manager, iam, cognito
│   ├── observability/            # cloudwatch, xray, tempo-storage, otel-collector-irsa
│   └── dr-automation/            # Lambda failover functions
│
└── global/                       # Cross-region resources
```

## K8s Manifest Structure

```
k8s/
├── base/                         # Shared namespace definitions
├── services/
│   ├── core/                     # Per-service: deployment, service, hpa, pdb
│   ├── user/
│   ├── fulfillment/
│   ├── business/
│   └── platform/
├── infra/
│   ├── karpenter/                # NodePool, EC2NodeClass CRDs
│   ├── otel-collector/           # OTel Collector config
│   └── argocd/apps/              # ApplicationSet definitions
└── overlays/
    ├── us-east-1/                # Region-specific patches (real endpoints)
    └── us-west-2/                # Region-specific patches
```

## State Management

| State | S3 Key | Resources |
|-------|--------|-----------|
| us-east-1 | `production/us-east-1/terraform.tfstate` | ~260 |
| us-west-2 | `production/us-west-2/terraform.tfstate` | ~260 |

:::warning 동시 Apply 금지
Concurrent terraform applies는 state drift를 유발합니다. 항상 `terraform plan`으로 상태를 확인한 후 apply하세요.
:::

## Post-Deployment Verification

```bash
# 트래픽 흐름 검증 스크립트
bash scripts/test-traffic-flow.sh
```

검증 항목:
- DNS resolution
- NLB 존재 확인
- Target group health
- CloudFront connectivity
- Route53 records
- **SG audit (no 0.0.0.0/0)**
- CloudFront origin 설정

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-region shopping mall platform on AWS. Three regions: **us-east-1** (primary), **us-west-2** (secondary), **ap-northeast-2** (Korea, multi-AZ). Write-Primary/Read-Local data pattern with Aurora Global Write Forwarding. 20 microservices across 5 domains.

- **AWS Account**: `<AWS_ACCOUNT_ID>` (sanitized for public repo; set via `.env.example`)
- **Domain**: atomai.click (wildcard cert `*.atomai.click`)
- **EKS Clusters**:
  - us-east-1 / us-west-2: `multi-region-mall`
  - ap-northeast-2: `mall-apne2-mgmt` (management), `mall-apne2-az-a`, `mall-apne2-az-c` (workload)

## Traffic Flow

```
User → mall.atomai.click → CloudFront + WAF
     → api-internal.atomai.click (Route53 latency-based → nearest NLB)
     → NLB (SG: CloudFront prefix list only)
     → api-gateway pods (EKS)
```

## Common Commands

### Terraform

```bash
# State backend: S3 bucket "multi-region-mall-terraform-state" + DynamoDB lock
cd terraform/environments/production/us-east-1  # or us-west-2
terraform init
terraform plan
terraform apply

# Korea region (layered: shared → eks-mgmt → eks-az-a → eks-az-c)
cd terraform/environments/production/ap-northeast-2/shared   # or eks-mgmt, eks-az-a, eks-az-c
terraform init && terraform plan

# Global resources (Aurora global cluster, DocumentDB global cluster, Route53 zone, state bucket)
cd terraform/global/<resource>/
terraform init && terraform plan
```

### Kubernetes / Kustomize

```bash
# Build overlay to verify (no kustomize binary — use kubectl)
kubectl kustomize k8s/overlays/us-east-1/
kubectl kustomize k8s/overlays/us-west-2/
kubectl kustomize k8s/overlays/ap-northeast-2-az-a/
kubectl kustomize k8s/overlays/ap-northeast-2-az-c/

# Apply (ArgoCD manages deployments — prefer GitOps over manual apply)
kubectl apply -k k8s/overlays/us-east-1/ --context arn:aws:eks:us-east-1:<AWS_ACCOUNT_ID>:cluster/multi-region-mall

# Check cluster status (US uses full ARN context, Korea uses short alias)
kubectl get nodes --context arn:aws:eks:us-east-1:<AWS_ACCOUNT_ID>:cluster/multi-region-mall
kubectl get pods -A --context mall-apne2-az-a   # Korea AZ-A
kubectl get pods -A --context mall-apne2-az-c   # Korea AZ-C
kubectl get pods -A --context mall-apne2-mgmt   # Korea management
```

### Microservice Build

```bash
# All services (from repo root)
scripts/build-and-push.sh

# Individual service (Go example)
cd src/services/cart
go build ./...
go test ./...

# Java services use Maven, Python services use pytest
```

## Architecture

### Terraform Structure

- `terraform/environments/production/{us-east-1,us-west-2}/` — Root modules per US region
- `terraform/environments/production/ap-northeast-2/` — Korea region (subdirs: `shared/`, `eks-mgmt/`, `eks-az-a/`, `eks-az-c/`)
- `terraform/modules/` — Reusable modules: `compute/`, `data/`, `dr-automation/`, `edge/`, `networking/`, `observability/`, `security/`
- `terraform/global/` — Cross-region resources (Aurora global cluster, DocumentDB global cluster, Route53 zone, state bucket)
- Provider: `hashicorp/aws >= 6.0`, Terraform `>= 1.9`

### K8s Structure

- `k8s/base/` — Shared namespace definitions
- `k8s/services/{core,user,fulfillment,business,platform}/` — Per-service deployments (20 services + synthetic-monitor CronJob)
- `k8s/infra/` — Infrastructure components (19): ArgoCD (US + Korea), ClickHouse (+ mgmt), Grafana (+ Korea NLB), Karpenter (US + 3 Korea), KEDA, OTel Collector, Prometheus Stack, Tempo (+ West), External Secrets, StorageClass, Actions Runner
- `k8s/overlays/{us-east-1,us-west-2,ap-northeast-2-az-a,ap-northeast-2-az-c}/` — Region-specific Kustomize overlays
- `k8s/infra/argocd/` — ArgoCD ApplicationSets for US clusters
- `k8s/infra/argocd-korea/` — ArgoCD ApplicationSets for Korea clusters (managed from mgmt cluster)

### Microservices (src/services/)

5 Go/Gin, 7 Java/Spring Boot, 8 Python/FastAPI — organized into domains:
- **Core (6)**: product-catalog (Python), inventory (Go), search (Go), cart (Go), order (Java), payment (Java)
- **User (4)**: user-account (Java), user-profile (Python), wishlist (Python), review (Python)
- **Fulfillment (3)**: shipping (Python), warehouse (Java), returns (Java)
- **Business (4)**: pricing (Java), notification (Python), recommendation (Python), seller (Java)
- **Platform (4)**: api-gateway (Go), event-bus (Go), analytics (Python), synthetic-monitor (Python CronJob)

## Key Conventions

### Terraform Naming

- IAM roles in us-east-1 use `role_name_suffix = ""` (no region suffix) — these were created before the suffix convention was added. us-west-2 uses `-us-west-2` suffix.
- DocumentDB us-east-1 primary uses `cluster_identifier_override = "production-docdb-global-primary"` (restored from snapshot, non-standard name).
- OpenSearch domain names max 28 chars — uses shortened region codes (`use1`, `usw2`).
- ElastiCache secondary: `engine`, `engine_version`, encryption params must be null (inherited from global datastore). `automatic_failover_enabled` in lifecycle `ignore_changes`.

### K8s / Kustomize

- Region-specific config (SG IDs, subnet IDs, ACM cert ARNs, data store endpoints) applied via JSON patches in overlays.
- Ingress uses `alb.ingress.kubernetes.io/security-groups` annotation pointing to Terraform-managed ALB SG (CloudFront prefix list restricted).
- `manage-backend-security-group-rules: "false"` prevents ALB Controller from creating its own SGs.

### Security

- **All public traffic MUST flow through CloudFront.** Direct ALB access is prohibited.
- ALB SGs restricted to CloudFront managed prefix list (`com.amazonaws.global.cloudfront.origin-facing`) — NOT `0.0.0.0/0`.
- Single port-range rule (80-443) due to prefix list entries (45) × rules quota limit (60).
- **NEVER create `0.0.0.0/0` inbound rules on any security group.** All SGs are managed by Terraform.
- **K8s Ingress**: MUST include `alb.ingress.kubernetes.io/security-groups` annotation referencing the Terraform-managed ALB SG. MUST include `alb.ingress.kubernetes.io/manage-backend-security-group-rules: "false"` to prevent ALB Controller from auto-creating SGs.
- **K8s Service type: LoadBalancer**: MUST use `service.beta.kubernetes.io/aws-load-balancer-security-groups` annotation referencing the Terraform-managed ALB SG. Never let the controller auto-generate SGs — they default to `0.0.0.0/0`.
- Terraform-managed ALB SG IDs: us-east-1 `sg-0123456789abcdef0`, us-west-2 `sg-0abcdef1234567890`.

### Post-Deployment Verification

- After `terraform apply` or `kubectl apply` that changes networking, load balancers, or ingress, **always run** `bash scripts/test-traffic-flow.sh` to verify the traffic flow.
- The script checks: DNS resolution, NLB existence, target group health, CloudFront connectivity, Route53 records, SG audit (no 0.0.0.0/0), and CloudFront origin.
- `WARN` for empty target groups is expected when pods are not yet deployed (nginx:alpine placeholders).

### Observability

- **OTel Collector** (DaemonSet): traces → ClickHouse + Tempo + X-Ray (via `spanmetrics` connector → Prometheus), logs → ClickHouse (filelog receiver, replaced Fluent Bit).
- **ClickHouse**: Trace/log analytics storage (`otel` database, 30-day TTL).
- **Grafana Tempo**: Distributed tracing backend (S3 storage, TraceQL queries).
- **Prometheus + Grafana**: Metrics collection and dashboards. Exemplar-storage enabled for trace↔metric correlation.
- **X-Ray**: AWS-native trace viewer (dual export from OTel).
- Korea observability runs on mgmt cluster; workload clusters export via internal NLBs.

### Frontend

- `src/frontend/`: React 19 + Vite 8 + Tailwind CSS 4 SPA.
- Deploy: `scripts/deploy-frontend.sh` (builds, uploads to S3, invalidates CloudFront).

### Scripts

- `scripts/build-and-push.sh` — Build and push all 20 service images to ECR (requires `$AWS_ACCOUNT_ID`)
- `scripts/deploy-frontend.sh` — Frontend deploy to S3 + CloudFront invalidation
- `scripts/test-traffic-flow.sh` — Post-deployment traffic flow verification
- `scripts/validate-korea-mgmt.sh` — Korea management cluster validation
- `scripts/generate-trace-traffic.sh` — Generate synthetic trace traffic
- `scripts/seed-data/` — Mock data seeding for all data stores

### EKS / Karpenter

- Bootstrap node group: 2× m5.large (system workloads: Karpenter, ArgoCD, CoreDNS). Taint: `node-role=system-critical:NoSchedule`.
- Karpenter v1.9 provisions application nodes via 6 NodePools: general, critical, api-tier, worker-tier, batch-tier, memory-tier.
- EC2NodeClass uses `role: multi-region-mall-node-group` (global IAM role works in both regions).
- Korea has separate Karpenter configs per cluster: `karpenter-apne2-mgmt`, `karpenter-apne2-az-a`, `karpenter-apne2-az-c`.

### Korea Region (ap-northeast-2)

- **3-cluster architecture**: mgmt (observability + ArgoCD + self-hosted runners), az-a and az-c (workload, ~115 pods each).
- ArgoCD Korea managed from mgmt cluster via `k8s/infra/argocd-korea/`. US ArgoCD does NOT manage Korea.
- kubectl contexts use short aliases: `mall-apne2-mgmt`, `mall-apne2-az-a`, `mall-apne2-az-c`.
- ALB Controller IRSA role names: `mall-apne2-az-{a,c}-alb-controller-*` (not `production-*` prefix).
- Self-hosted GitHub Actions runners (ARC v2): x86 + arm64 via Karpenter on mgmt cluster.

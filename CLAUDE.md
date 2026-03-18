# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-region shopping mall platform on AWS. Two active regions: **us-east-1** (primary) and **us-west-2** (secondary). Write-Primary/Read-Local data pattern with Aurora Global Write Forwarding. 20 microservices across 5 domains, currently running nginx:alpine placeholders.

- **AWS Account**: 180294183052
- **Domain**: atomai.click (wildcard cert `*.atomai.click`)
- **EKS Cluster**: `multi-region-mall` in both regions

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

# Global resources (Aurora global cluster, DocumentDB global cluster, Route53 zone, state bucket)
cd terraform/global/<resource>/
terraform init && terraform plan
```

### Kubernetes / Kustomize

```bash
# Build overlay to verify (no kustomize binary — use kubectl)
kubectl kustomize k8s/overlays/us-east-1/
kubectl kustomize k8s/overlays/us-west-2/

# Apply (ArgoCD manages deployments — prefer GitOps over manual apply)
kubectl apply -k k8s/overlays/us-east-1/ --context arn:aws:eks:us-east-1:180294183052:cluster/multi-region-mall

# Check cluster status
kubectl get nodes --context arn:aws:eks:us-east-1:180294183052:cluster/multi-region-mall
kubectl get pods -A --context arn:aws:eks:us-east-1:180294183052:cluster/multi-region-mall
```

### Microservice Build

```bash
# All services (from repo root)
scripts/build-and-push.sh

# Individual service (Go example)
cd src/services/product-catalog-service
go build ./...
go test ./...

# Java services use Maven, Python services use pytest
```

## Architecture

### Terraform Structure

- `terraform/environments/production/{us-east-1,us-west-2}/` — Root modules per region, each calls shared modules
- `terraform/modules/` — Reusable modules: `compute/`, `data/`, `edge/`, `networking/`, `observability/`, `security/`
- `terraform/global/` — Cross-region resources (Aurora global cluster, DocumentDB global cluster, Route53 zone, state bucket)
- Provider: `hashicorp/aws >= 6.0`, Terraform `>= 1.9`

### K8s Structure

- `k8s/base/` — Shared namespace definitions
- `k8s/services/{core,user,fulfillment,business,platform}/` — Per-service deployments (20 services)
- `k8s/infra/` — Karpenter NodePools/EC2NodeClasses, OTel Collector, Ingress
- `k8s/overlays/{us-east-1,us-west-2}/` — Region-specific Kustomize overlays with real AWS endpoints
- `k8s/infra/argocd/` — ArgoCD Application and ApplicationSet definitions

### Microservices (src/services/)

5 Go/Gin, 7 Java/Spring Boot, 8 Python/FastAPI — organized into domains:
- **Core**: product-catalog, inventory, pricing, search (Go)
- **User**: user, notification, recommendation (Java/Python)
- **Fulfillment**: order, payment, shipping, delivery-tracking (Java/Go)
- **Business**: seller, analytics, promotion, review (Python/Java)
- **Platform**: api-gateway (Go), event-processor, media, config (Python/Java)

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
- Terraform-managed ALB SG IDs: us-east-1 `sg-048c7e63db40686b8`, us-west-2 `sg-0bfd63c6e6188327b`.

### Post-Deployment Verification

- After `terraform apply` or `kubectl apply` that changes networking, load balancers, or ingress, **always run** `bash scripts/test-traffic-flow.sh` to verify the traffic flow.
- The script checks: DNS resolution, NLB existence, target group health, CloudFront connectivity, Route53 records, SG audit (no 0.0.0.0/0), and CloudFront origin.
- `WARN` for empty target groups is expected when pods are not yet deployed (nginx:alpine placeholders).

### EKS / Karpenter

- Bootstrap node group: 2× m5.large (system workloads: Karpenter, ArgoCD, CoreDNS).
- Karpenter v1.9 provisions application nodes via 6 NodePools: general, critical, api-tier, worker-tier, batch-tier, memory-tier.
- EC2NodeClass uses `role: multi-region-mall-node-group` (global IAM role works in both regions).

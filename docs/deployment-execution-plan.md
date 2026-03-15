# Multi-Region Shopping Mall - Deployment Execution Plan

## Document Information

| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | 2026-03-15 |
| Status | In Progress |
| Classification | Internal |

---

## Execution Overview

```
Phase 1: Preparation          Phase 3: GitOps (parallel)
┌──────────────────┐          ┌──────────────────────┐
│ 1.1 tfvars       │──┐       │ 3.1 ArgoCD manifests │
│ 1.2 ACM cert     │  │       │ 3.2 ApplicationSets  │
│ 1.3 Domain setup │  │       │ 3.3 Root App         │
└──────────────────┘  │       └──────────────────────┘
                      │
Phase 2: Terraform    ▼
┌──────────────────────────────────────────┐
│ 2.1 State Backend (S3 + DynamoDB)        │
│          ▼                               │
│ 2.2 Global Resources (Aurora/DocDB GC)   │
│          ▼                               │
│ 2.3 us-east-1 Primary (~30-45 min)       │
│          ▼                               │
│ 2.4 us-west-2 Secondary (~30-45 min)     │
└──────────────────────────────────────────┘
                      │
Phase 4: K8s Deploy   ▼
┌──────────────────────────────────────────┐
│ 4.1 ArgoCD install (us-east-1 EKS)      │
│ 4.2 Register us-west-2 cluster          │
│ 4.3 Deploy Root App → auto-sync 40 apps │
└──────────────────────────────────────────┘
                      │
Phase 5: Verify       ▼
┌──────────────────────────────────────────┐
│ 5.1 Terraform outputs validation         │
│ 5.2 ArgoCD sync status                  │
│ 5.3 End-to-end health checks            │
└──────────────────────────────────────────┘
```

---

## Phase 1: Preparation

### Step 1.1: Update terraform.tfvars

**Files:**
- `terraform/environments/production/us-east-1/terraform.tfvars`
- `terraform/environments/production/us-west-2/terraform.tfvars`

**Changes:**

| Variable | Old Value | New Value |
|----------|-----------|-----------|
| domain_name | example.com | atomai.click |
| route53_zone_id | PLACEHOLDER | Z01703432E9KT1G1FIRFM |
| acm_certificate_arn (us-east-1) | PLACEHOLDER | arn:aws:acm:us-east-1:180294183052:certificate/f6b6907a-... |
| acm_certificate_arn (us-west-2) | PLACEHOLDER | (created in Step 1.2) |

### Step 1.2: Create us-west-2 ACM Certificate

```bash
# Request wildcard certificate
aws acm request-certificate \
  --region us-west-2 \
  --domain-name "*.atomai.click" \
  --subject-alternative-names "atomai.click" \
  --validation-method DNS

# Add DNS validation record to Route53
# Wait for validation to complete (~5 min)
aws acm wait certificate-validated \
  --region us-west-2 \
  --certificate-arn <new-cert-arn>
```

### Step 1.3: Verify Domain Configuration

- Ensure Route53 zone Z01703432E9KT1G1FIRFM is accessible
- Confirm us-east-1 ACM cert is valid and issued

---

## Phase 2: Terraform Deployment

### Step 2.1: State Backend

```bash
cd terraform/global/terraform-state
terraform init
terraform apply -auto-approve
```

**Creates:**
- S3 bucket: `multi-region-mall-terraform-state`
- DynamoDB table: `multi-region-mall-terraform-locks`

### Step 2.2: Global Resources

```bash
# Aurora Global Cluster
cd terraform/global/aurora-global-cluster
terraform init && terraform apply -auto-approve

# DocumentDB Global Cluster
cd terraform/global/documentdb-global-cluster
terraform init && terraform apply -auto-approve
```

**Creates:**
- Aurora PostgreSQL 15.4 global cluster: `multi-region-mall-aurora`
- DocumentDB 5.0 global cluster: `multi-region-mall-docdb`

### Step 2.3: us-east-1 Primary Region

```bash
cd terraform/environments/production/us-east-1
terraform init \
  -backend-config="bucket=multi-region-mall-terraform-state" \
  -backend-config="key=production/us-east-1/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=multi-region-mall-terraform-locks"

terraform plan -out=tfplan
terraform apply tfplan
```

**Expected duration:** 30-45 minutes
**Resource creation order (automatic via dependency graph):**
1. VPC + Subnets + NAT Gateways
2. Security Groups + KMS Keys + Secrets Manager
3. Transit Gateway
4. EKS Cluster + Node Groups
5. ALB Controller IAM
6. Aurora Primary Cluster + Instances
7. DocumentDB Primary Cluster + Instances
8. ElastiCache (Valkey) Primary Replication Group
9. MSK Cluster (6 brokers)
10. OpenSearch Domain
11. S3 Buckets
12. Route53 Records
13. CloudFront Distribution
14. WAF Web ACL
15. CloudWatch Dashboards + Alarms
16. X-Ray Groups

### Step 2.4: us-west-2 Secondary Region

```bash
cd terraform/environments/production/us-west-2
terraform init \
  -backend-config="bucket=multi-region-mall-terraform-state" \
  -backend-config="key=production/us-west-2/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=multi-region-mall-terraform-locks"

terraform plan -out=tfplan
terraform apply tfplan
```

**Expected duration:** 30-45 minutes
**Additional cross-region resources:**
- Transit Gateway Peering (to us-east-1 TGW)
- Aurora Secondary Cluster (joins global cluster)
- DocumentDB Secondary Cluster (joins global cluster)
- ElastiCache Secondary (joins global replication group)
- MSK Replicator (replicates topics from us-east-1)
- S3 Cross-Region Replication

---

## Phase 3: ArgoCD + App-of-ApplicationSets (Parallel with Phase 2)

### Step 3.1: Create Manifests

**New files to create:**
```
k8s/infra/argocd/
├── kustomization.yaml          # Kustomize entry point
├── namespace.yaml              # argocd namespace
├── install.yaml                # ArgoCD HA manifests
└── apps/
    ├── kustomization.yaml      # Apps kustomization
    ├── root-app.yaml           # App-of-Apps root Application
    ├── appset-core.yaml        # Core services (6 svc x 2 clusters)
    ├── appset-user.yaml        # User services (4 svc x 2 clusters)
    ├── appset-fulfillment.yaml # Fulfillment (3 svc x 2 clusters)
    ├── appset-business.yaml    # Business services (4 svc x 2 clusters)
    ├── appset-platform.yaml    # Platform (3 svc x 2 clusters)
    └── appset-infra.yaml       # Infrastructure (karpenter, etc.)
```

### Step 3.2: ArgoCD Configuration

- **Installation method:** Kustomize (consistent with existing patterns)
- **Mode:** HA (3 replicas for server, repo-server, controller)
- **Namespace:** argocd
- **Sync policy:** Automated with prune + self-heal
- **Repository:** https://github.com/Atom-oh/multi-region-architecture.git

### Step 3.3: ApplicationSet Generator Strategy

Each ApplicationSet uses the `clusters` generator with region label matching:
- In-cluster (us-east-1): labeled `region=us-east-1`
- External (us-west-2): labeled `region=us-west-2` after `argocd cluster add`

---

## Phase 4: K8s Deployment

### Step 4.1: Install ArgoCD

```bash
aws eks update-kubeconfig --name multi-region-mall --region us-east-1
kubectl apply -k k8s/infra/argocd/
```

### Step 4.2: Register us-west-2 Cluster

```bash
argocd login <argocd-server-url>
argocd cluster add arn:aws:eks:us-west-2:180294183052:cluster/multi-region-mall \
  --label region=us-west-2
```

### Step 4.3: Deploy Root App

```bash
kubectl apply -f k8s/infra/argocd/apps/root-app.yaml
```

ArgoCD auto-creates:
- 6 ApplicationSets → ~40 Applications (20 services x 2 clusters)
- Each Application syncs Kustomize overlay per region

---

## Phase 5: Verification Checklist

### 5.1 Terraform Verification

- [ ] `terraform output` returns all endpoints for both regions
- [ ] Aurora Global: replication lag < 100ms
- [ ] DocumentDB Global: secondary cluster healthy
- [ ] ElastiCache: global replication group active
- [ ] MSK Replicator: topic replication active
- [ ] CloudFront distribution deployed

### 5.2 ArgoCD Verification

- [ ] `argocd app list` shows all apps Synced/Healthy
- [ ] Both clusters registered and reachable
- [ ] ArgoCD UI accessible

### 5.3 End-to-End Verification

- [ ] ALB health checks passing (both regions)
- [ ] Route53 latency records resolving correctly
- [ ] CloudFront serving static assets
- [ ] WAF rules active
- [ ] CloudWatch dashboards populated
- [ ] X-Ray traces flowing

---

## Rollback Plan

### Terraform Rollback

```bash
# Reverse order: us-west-2 → us-east-1 → global → state
cd terraform/environments/production/us-west-2
terraform destroy -auto-approve

cd terraform/environments/production/us-east-1
terraform destroy -auto-approve

cd terraform/global/aurora-global-cluster
terraform destroy -auto-approve

cd terraform/global/documentdb-global-cluster
terraform destroy -auto-approve
```

### ArgoCD Rollback

```bash
kubectl delete -f k8s/infra/argocd/apps/root-app.yaml
kubectl delete -k k8s/infra/argocd/
```

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Aurora global cluster creation timeout | High | Retry with increased timeout; check service quotas |
| MSK Replicator requires both clusters | Medium | Deploy primary first, enable replicator in secondary only |
| ACM cert DNS validation delay | Low | Pre-create cert, allow 5-30 min for validation |
| EKS addon version mismatch | Medium | Pin addon versions in Terraform module |
| Cross-region TGW peering acceptance | Medium | Both regions in same account = auto-accept |

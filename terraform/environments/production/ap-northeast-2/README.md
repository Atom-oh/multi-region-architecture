# ap-northeast-2 (Korea) — Multi-AZ Deployment

Independent Korean region with multi-AZ architecture. Standalone data stores (no global cluster participation).

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │       ap-northeast-2 (Korea)        │
                    │                                     │
                    │  ┌───────────┐  ┌───────────────┐   │
                    │  │  eks-mgmt │  │    shared/     │   │
                    │  │  (ArgoCD, │  │  (VPC, Data,   │   │
                    │  │  Runners, │  │   NLB, IAM)    │   │
                    │  │  OTel)    │  └───────────────┘   │
                    │  └───────────┘                      │
                    │  ┌──────────┐  ┌──────────┐         │
                    │  │ eks-az-a │  │ eks-az-c │         │
                    │  │ (AZ-A    │  │ (AZ-C    │         │
                    │  │  pods)   │  │  pods)   │         │
                    │  └──────────┘  └──────────┘         │
                    └─────────────────────────────────────┘
```

## Layers

| Layer | State Key | Description |
|-------|-----------|-------------|
| `shared/` | `production/ap-northeast-2/shared/terraform.tfstate` | VPC, Security Groups, KMS, Secrets, IAM, Aurora, DocumentDB, ElastiCache, MSK, OpenSearch, NLB (weighted), S3 |
| `eks-mgmt/` | `production/ap-northeast-2/eks-mgmt/terraform.tfstate` | Management EKS cluster (ArgoCD, GitHub Runners, OTel) |
| `eks-az-a/` | `production/ap-northeast-2/eks-az-a/terraform.tfstate` | Workload EKS cluster in AZ-A (~115 pods) |
| `eks-az-c/` | `production/ap-northeast-2/eks-az-c/terraform.tfstate` | Workload EKS cluster in AZ-C (~115 pods) |

## Deployment Order

```
shared/  →  eks-mgmt/  →  eks-az-a/  (parallel)
                       →  eks-az-c/  (parallel)
```

### 1. shared/ (Foundation)

```bash
cd terraform/environments/production/ap-northeast-2/shared
terraform init
terraform plan
terraform apply
```

Creates: VPC (10.2.0.0/16), all data stores, weighted NLB, security groups, KMS keys, IAM roles (including GitHub Actions OIDC).

### 2. eks-mgmt/ (Management Cluster)

```bash
cd terraform/environments/production/ap-northeast-2/eks-mgmt
terraform init
terraform plan
terraform apply
```

Reads `shared/` state for VPC, subnets, security groups, KMS keys.
Creates: `mall-apne2-mgmt` EKS cluster (m5.xlarge nodes), ALB controller IRSA, OTel IRSA, Tempo storage.

### 3. eks-az-a/ and eks-az-c/ (Workload Clusters)

```bash
# Can run in parallel
cd terraform/environments/production/ap-northeast-2/eks-az-a
terraform init && terraform plan && terraform apply

cd terraform/environments/production/ap-northeast-2/eks-az-c
terraform init && terraform plan && terraform apply
```

Reads `shared/` and `eks-mgmt/` states. Creates workload EKS clusters with ALB controller, OTel, Tempo.

## Remote State Dependencies

```
shared/  ──read by──>  eks-mgmt/
shared/  ──read by──>  eks-az-a/
shared/  ──read by──>  eks-az-c/
eks-mgmt/ ──read by──> eks-az-a/  (ArgoCD cross-cluster SG)
eks-mgmt/ ──read by──> eks-az-c/  (ArgoCD cross-cluster SG)
```

## Key Differences from US Regions

| Aspect | US (Multi-Region) | Korea (Multi-AZ) |
|--------|-------------------|-------------------|
| EKS clusters | 1 multi-AZ per region | 3: mgmt + AZ-A + AZ-C |
| NLB | Standard (single TG) | Weighted (50/50 AZ-A, AZ-C) |
| Data stores | Global clusters, DSQL | Standalone, Aurora PostgreSQL |
| Transit Gateway | Cross-region peering | None |
| CloudFront/WAF | us-east-1 manages | Inline in shared/ (ArgoCD, Grafana only) |

## kubectl Contexts

```bash
kubectl get pods -A --context mall-apne2-mgmt    # Management
kubectl get pods -A --context mall-apne2-az-a     # Workload AZ-A
kubectl get pods -A --context mall-apne2-az-c     # Workload AZ-C
```

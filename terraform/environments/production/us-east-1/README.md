# us-east-1 (Primary) — Multi-Region Deployment

Primary region for the multi-region shopping mall. Hosts global resources (CloudFront, WAF, Cognito, Route53 records) and primary data stores (Aurora, DocumentDB, ElastiCache primaries).

## Architecture

```
                    ┌──────────────────────────────────────┐
                    │        us-east-1 (Primary)           │
                    │                                      │
                    │  ┌──────────┐   ┌──────────┐         │
                    │  │ shared/  │   │   eks/   │         │
                    │  │ (VPC,    │──>│ (EKS,    │         │
                    │  │  Data,   │   │  IRSA,   │         │
                    │  │  NLB,    │   │  OTel)   │         │
                    │  │  IAM)    │   └──────────┘         │
                    │  └──────────┘                        │
                    │       │          ┌──────────┐        │
                    │       └─────────>│  edge/   │        │
                    │                  │ (CF,WAF, │        │
                    │                  │  R53,    │        │
                    │                  │  Cognito)│        │
                    │                  └──────────┘        │
                    │       │          ┌──────────┐        │
                    │       └─────────>│   dr/    │        │
                    │                  │ (Lambda  │        │
                    │                  │  failover│        │
                    │                  │  automation)      │
                    │                  └──────────┘        │
                    └──────────────────────────────────────┘
```

## Layers

| Layer | State Key | Description |
|-------|-----------|-------------|
| `shared/` | `production/us-east-1/shared/terraform.tfstate` | VPC, Transit Gateway, Security Groups, KMS, Secrets Manager, IAM, NLB, DSQL, DocumentDB (primary), ElastiCache (primary), MSK, OpenSearch, S3 |
| `eks/` | `production/us-east-1/eks/terraform.tfstate` | EKS cluster, ALB Controller IRSA, DSQL IRSA, Tempo storage, OTel IRSA, CloudWatch, X-Ray |
| `edge/` | `production/us-east-1/edge/terraform.tfstate` | WAF, CloudFront (main + ArgoCD + Grafana), Route53 records, Cognito, KMS key policy for CloudFront OAC |
| `dr/` | `production/us-east-1/dr/terraform.tfstate` | DR automation Lambda (DocumentDB + ElastiCache failover), SNS notifications |

## Deployment Order

```
shared/  →  eks/   (sequential — eks needs OIDC provider)
         →  edge/  (parallel with eks — needs NLB, S3, KMS from shared)
         →  dr/    (parallel with eks — needs ElastiCache global group from shared)
```

### 1. shared/ (Foundation)

```bash
cd terraform/environments/production/us-east-1/shared
terraform init
terraform plan
terraform apply
```

Creates: VPC (10.0.0.0/16), Transit Gateway, all data stores (primaries), NLB, security groups, KMS keys, IAM roles.

### 2. eks/ (Compute)

```bash
cd terraform/environments/production/us-east-1/eks
terraform init
terraform plan
terraform apply
```

Reads `shared/` state for VPC, subnets, security groups, KMS keys, DSQL ARN.
Creates: `multi-region-mall` EKS cluster, ALB controller IRSA, observability IRSA roles, CloudWatch alarms.

### 3. edge/ (CDN + DNS)

```bash
cd terraform/environments/production/us-east-1/edge
terraform init
terraform plan
terraform apply
```

Reads `shared/` state for S3 bucket domain, NLB DNS, KMS key IDs.
Creates: CloudFront distributions (main, ArgoCD, Grafana), WAF, Route53 records, Cognito user pool.

### 4. dr/ (Disaster Recovery)

```bash
cd terraform/environments/production/us-east-1/dr
terraform init
terraform plan
terraform apply
```

Reads `shared/` state for ElastiCache global replication group ID.
Creates: Lambda functions for DocumentDB/ElastiCache failover, SNS topic for DR alerts.

## Remote State Dependencies

```
shared/  ──read by──>  eks/
shared/  ──read by──>  edge/
shared/  ──read by──>  dr/
```

## State Migration (from monolithic)

The existing monolithic state is at `production/us-east-1/terraform.tfstate`. To migrate:

```bash
# 1. Import existing resources into layered states using terraform import
# 2. Or use terraform state mv to move resources between state files
# Example:
#   terraform state mv -state=terraform.tfstate -state-out=shared/terraform.tfstate 'module.vpc' 'module.vpc'
#   terraform state mv -state=terraform.tfstate -state-out=eks/terraform.tfstate 'module.eks' 'module.eks'

# WARNING: Do not run layered terraform apply until state migration is complete.
# The monolithic main.tf and layered configs manage the same resources.
```

## Primary-Only Resources

These resources exist only in us-east-1:
- CloudFront distributions (main, ArgoCD, Grafana)
- WAF Web ACL
- Cognito user pool
- DR automation Lambda
- Route53 alias records for CloudFront
- S3 replication role (global IAM role)
- DocumentDB primary cluster (`production-docdb-global-primary`)
- ElastiCache primary replication group

## kubectl Context

```bash
kubectl get pods -A --context arn:aws:eks:us-east-1:<AWS_ACCOUNT_ID>:cluster/multi-region-mall
```

# us-west-2 (Secondary) — Multi-Region Deployment

Secondary region for the multi-region shopping mall. Hosts read replicas of all data stores and a latency-based Route53 record for the NLB. CloudFront, WAF, and Cognito are managed from us-east-1.

## Architecture

```
                    ┌──────────────────────────────────────┐
                    │       us-west-2 (Secondary)          │
                    │                                      │
                    │  ┌──────────┐   ┌──────────┐         │
                    │  │ shared/  │   │   eks/   │         │
                    │  │ (VPC,    │──>│ (EKS,    │         │
                    │  │  Data    │   │  IRSA,   │         │
                    │  │  replicas│   │  OTel)   │         │
                    │  │  NLB)    │   └──────────┘         │
                    │  └──────────┘                        │
                    │       │          ┌──────────┐        │
                    │       └─────────>│  edge/   │        │
                    │                  │ (Route53 │        │
                    │                  │  latency)│        │
                    │                  └──────────┘        │
                    └──────────────────────────────────────┘
                              │
                              │ TGW peering
                              ▼
                    ┌──────────────────────────────────────┐
                    │        us-east-1 (Primary)           │
                    │  shared/ state read for:             │
                    │  - transit_gateway_id                │
                    │  - elasticache_global_replication_id │
                    │  - msk_cluster_arn                   │
                    └──────────────────────────────────────┘
```

## Layers

| Layer | State Key | Description |
|-------|-----------|-------------|
| `shared/` | `production/us-west-2/shared/terraform.tfstate` | VPC, Transit Gateway (peering to us-east-1), Security Groups, KMS, Secrets Manager, IAM, NLB, DSQL, DocumentDB (replica), ElastiCache (replica), MSK, OpenSearch, S3 |
| `eks/` | `production/us-west-2/eks/terraform.tfstate` | EKS cluster, ALB Controller IRSA, DSQL IRSA, Tempo storage, OTel IRSA, CloudWatch, X-Ray |
| `edge/` | `production/us-west-2/edge/terraform.tfstate` | Route53 latency-based record (points NLB to api-internal.atomai.click) |

## Deployment Order

```
[us-east-1/shared must exist first — TGW peering + ElastiCache global group]

shared/  →  eks/   (sequential)
         →  edge/  (parallel with eks)
```

### 1. shared/ (Foundation)

```bash
cd terraform/environments/production/us-west-2/shared
terraform init
terraform plan
terraform apply
```

Reads `us-east-1/shared` state for Transit Gateway ID, ElastiCache global replication group, MSK cluster ARN.
Creates: VPC (10.1.0.0/16), Transit Gateway with cross-region peering, data store replicas, NLB.

### 2. eks/ (Compute)

```bash
cd terraform/environments/production/us-west-2/eks
terraform init
terraform plan
terraform apply
```

Reads `us-west-2/shared` state for VPC, subnets, security groups.
Creates: `multi-region-mall` EKS cluster, ALB controller IRSA, observability IRSA roles.

### 3. edge/ (DNS)

```bash
cd terraform/environments/production/us-west-2/edge
terraform init
terraform plan
terraform apply
```

Reads `us-west-2/shared` state for NLB DNS name and zone ID.
Creates: Route53 latency-based A record for `api-internal.atomai.click`.

## Remote State Dependencies

```
us-east-1/shared  ──read by──>  us-west-2/shared  (TGW, ElastiCache global, MSK)
us-west-2/shared  ──read by──>  us-west-2/eks
us-west-2/shared  ──read by──>  us-west-2/edge
```

## State Migration (from monolithic)

The existing monolithic state is at `production/us-west-2/terraform.tfstate`. To migrate:

```bash
# Use terraform state mv to split resources into layered states.
# WARNING: Do not run layered terraform apply until state migration is complete.
```

## Key Differences from us-east-1

| Aspect | us-east-1 (Primary) | us-west-2 (Secondary) |
|--------|--------------------|-----------------------|
| Data stores | Primary (write) | Replicas (read-local) |
| CloudFront/WAF | Yes (3 distributions) | No (managed from primary) |
| Cognito | Yes | No |
| DR automation | Yes (Lambda failover) | No (target of failover) |
| Transit Gateway | Creates TGW | Peers to us-east-1 TGW |
| Route53 | Full records (CF aliases) | Latency record only |
| ALB IRSA suffix | `""` (no suffix) | `"-us-west-2"` |
| OpenSearch SLR | Creates | Skips (`create_service_linked_role = false`) |

## kubectl Context

```bash
kubectl get pods -A --context arn:aws:eks:us-west-2:<AWS_ACCOUNT_ID>:cluster/multi-region-mall
```

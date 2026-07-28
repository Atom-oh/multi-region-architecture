# ap-northeast-2 (Korea) — Multi-AZ Deployment

Independent Korean region with multi-AZ architecture. Standalone data stores (no global cluster participation).

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │       ap-northeast-2 (Korea)        │
                    │                                     │
                    │  ┌───────────┐  ┌───────────────┐   │
                    │  │  eks-mgmt │  │    shared/     │   │
                    │  │ (ArgoCD,  │  │  (VPC, Data,   │   │
                    │  │  Runners, │  │   NLB, IAM)    │   │
                    │  │  OTel)    │  └───────────────┘   │
                    │  │ ⚠ owned   │                      │
                    │  │ elsewhere │                      │
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
| `eks-az-a/` | `production/ap-northeast-2/eks-az-a/terraform.tfstate` | Workload EKS cluster in AZ-A (~115 pods) |
| `eks-az-c/` | `production/ap-northeast-2/eks-az-c/terraform.tfstate` | Workload EKS cluster in AZ-C (~115 pods) |

The management cluster (`mall-apne2-mgmt`) is **not a layer in this repo**. Its
Terraform lives in the shared platform repo `AWS-Demo-Platform`
(`infra/eks-mgmt`, applied by that repo's Atlantis) and owns the state key
`production/ap-northeast-2/eks-mgmt/terraform.tfstate` in this same bucket.
Never apply that state from here — split-brain applies on a shared state
object are how you lose a cluster. Partially enforced: `github-actions-role`
carries an explicit `s3:PutObject`/`s3:DeleteObject` **Deny** on that key
(`externally_owned_state_keys` in `shared/main.tf`), which closes the CI path.
It binds that one principal only — a human with admin credentials, or any other
role, is still free to write the object, and the DynamoDB lock row and the mgmt
resources themselves are not covered. Rationale and the full contract:
`docs/decisions/ADR-003-eks-mgmt-ownership-handoff.md`.

## Deployment Order

```
shared/  →  eks-az-a/  (parallel)
         →  eks-az-c/  (parallel)
```

`mall-apne2-mgmt` must already exist (created from `AWS-Demo-Platform`) before
the spokes apply — they look it up live for its cluster SG, see below.

### 1. shared/ (Foundation)

```bash
cd terraform/environments/production/ap-northeast-2/shared
terraform init
terraform plan
terraform apply
```

Creates: VPC (10.2.0.0/16), all data stores, weighted NLB, security groups, KMS keys, IAM roles (including GitHub Actions OIDC).

### 2. eks-az-a/ and eks-az-c/ (Workload Clusters)

```bash
# Can run in parallel
cd terraform/environments/production/ap-northeast-2/eks-az-a
terraform init && terraform plan && terraform apply

cd terraform/environments/production/ap-northeast-2/eks-az-c
terraform init && terraform plan && terraform apply
```

Reads `shared/` state. Creates workload EKS clusters with ALB controller, OTel, Tempo.

Requires `eks:DescribeCluster` on `mall-apne2-mgmt`: both spokes need that
cluster's EKS-managed SG as an ingress source so mgmt's ArgoCD can reach their
API servers, and they read it with a live `data "aws_eks_cluster" "mgmt"`
lookup rather than a cross-repo `terraform_remote_state`. The grant is in
`shared/main.tf` (`describable_cluster_names`), scoped to that one cluster ARN
in `ap-northeast-2`. Note the coupling: `mgmt_cluster_name` in a spoke and
`describable_cluster_names` in `shared/` name the same cluster from two layers.
Renaming mgmt is therefore two-phase — add the new name to
`describable_cluster_names` and apply `shared/` **first**, or the spokes hit
`AccessDenied` on the lookup before any guard can report anything useful.

Three `postcondition`s guard the lookup: the cluster must sit in this region's
shared VPC, it must carry this platform's `ManagedBy=terraform` /
`Project=multi-region-mall` tags, and it must actually report a cluster SG
(empty would make the EKS module drop the ingress rule silently). That SG
becomes an ingress trust boundary on the workload API servers, so a name-only
match is not enough. Each guard has a deliberate release: `expected_mgmt_vpc_id`
for the VPC, `expected_mgmt_tags = {}` for the tags, and
`mgmt_cluster_security_group_id` to skip the lookup entirely.

## Runbooks

**mgmt cluster was recreated (SG ID changed).** Workloads keep serving — only
GitOps sync breaks, and only at the next sync, so this fails quietly:

1. `AWS-Demo-Platform` applies `infra/eks-mgmt`.
2. Here: `terraform apply` in **both** `eks-az-a/` and `eks-az-c/`.
3. On mgmt: `argocd cluster list` shows both spokes `Successful`.

**mgmt is down / moved / `eks:DescribeCluster` fails and you must apply a spoke.**
The live lookup makes mgmt a plan-time dependency, so set
`mgmt_cluster_security_group_id` — any non-null value drops the data source's
`count` to 0, removing both the API read and its postconditions:

```bash
# keep the ArgoCD ingress rule, using the SG ID you already know
terraform apply -var 'mgmt_cluster_security_group_id=sg-0123456789abcdef0'

# or drop the rule entirely — the EKS module skips it on ""
terraform apply -var 'mgmt_cluster_security_group_id='
```

Unset it once mgmt is back. Only GitOps reachability is affected — the
CloudFront → NLB → api-gateway traffic path does not use this SG.

## Remote State Dependencies

```
shared/  ──read by──>  eks-az-a/
shared/  ──read by──>  eks-az-c/
shared/  ──read by──>  AWS-Demo-Platform infra/eks-mgmt   (external)
```

No dependency on the `eks-mgmt` state — that state belongs to
`AWS-Demo-Platform`, and the one value the spokes need from it
(`cluster_security_group_id`) comes from the live-cluster lookup instead.

The arrow the other way is a real contract: `AWS-Demo-Platform` reads this
region's `shared/` outputs. These four are **breaking-change-frozen** — renaming
or retyping them breaks that repo's plan:

| Output | Used for |
|--------|----------|
| `vpc_id` | mgmt cluster VPC |
| `private_subnet_ids` | mgmt node placement |
| `internal_observability_nlb_security_group_id` | spoke → mgmt Tempo/Prometheus ingest |
| `kms_key_arns["s3"]` | mgmt-side Tempo bucket encryption |

The contract runs the other way too: the mgmt cluster must be created **in this
region's shared VPC** and tagged `ManagedBy=terraform` /
`Project=multi-region-mall`. Both spokes assert this before trusting mgmt's SG,
so dropping either breaks their plan, not just a convention.

Korea's **central** observability storage (mgmt-side Tempo S3 bucket + its IRSA)
is created by `AWS-Demo-Platform`. The per-AZ `tempo_storage` /
`otel_collector_irsa` modules in `eks-az-{a,c}` stay here.

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

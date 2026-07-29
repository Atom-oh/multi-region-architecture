# ap-northeast-2 (Korea) — Multi-AZ Deployment

Independent Korean region with multi-AZ architecture. Standalone data stores (no global cluster participation).

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │       ap-northeast-2 (Korea)        │
                    │                                     │
                    │  . . . . . . .  ┌───────────────┐   │
                    │  . eks-mgmt   .  │    shared/    │   │
                    │  . (ArgoCD,   .  │  (VPC, Data,  │   │
                    │  .  Runners,  .  │   NLB, IAM)   │   │
                    │  .  OTel)     .  └───────────────┘   │
                    │  . external:  .                      │
                    │  . AWS-Demo-  .                      │
                    │  . Platform   .                      │
                    │  . . . . . . .                       │
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
carries an explicit **Deny** on that key: `s3:GetObject`/`GetObjectVersion`/
`PutObject`/`PutObjectAcl`/`AbortMultipartUpload`/`DeleteObject`/
`DeleteObjectVersion` on the object, plus `PutItem`/`UpdateItem`/`DeleteItem`/
`BatchWriteItem`/`PartiQLInsert`/`PartiQLUpdate`/`PartiQLDelete` on its DynamoDB
lock rows, scoped with `dynamodb:LeadingKeys`. The versioned and batch/PartiQL
variants are separate IAM actions that reach the same object and rows, so a
shorter list is a bypassable list. `shared/main.tf` only passes the key list
(`externally_owned_state_keys`); the statements themselves live in
`terraform/modules/security/iam/github-actions.tf`.

That is one principal, not a boundary. A human with admin credentials, or any
other role, is still free to write the object — the lock-row Deny does not
follow them either — and nothing here restricts the mgmt resources themselves.
One such role is concrete and lives next door: the `ci_runner` role that
`AWS-Demo-Platform` now owns has `AmazonS3FullAccess` attached and is bound by
pod identity to ten runner service accounts, so any CI workload on the mgmt
cluster can read and write this whole state bucket. Closing that needs a bucket
policy here plus a narrower grant there; both are follow-up work, not part of
this handoff.
Rationale and the full contract:
`docs/decisions/ADR-003-eks-mgmt-ownership-handoff.md`.

## Deployment Order

```
shared/  →  mall-apne2-mgmt  →  eks-az-a/  (parallel)
           (external:           eks-az-c/  (parallel)
            AWS-Demo-Platform
            /infra/eks-mgmt)
```

`shared/` is first because the external mgmt layer *reads* its state — `vpc_id`,
`private_subnet_ids`, and the SG/KMS outputs below. The spokes are last because
they look mgmt up live for its cluster SG, at **plan** time, so on a cold
rebuild of the whole region the critical path runs through another repo's apply.
Budget that into the RTO: a Korea rebuild is not a single-repo operation.

Steady state, only the spokes' plan-time dependency is live — mgmt existing is a
precondition for planning `eks-az-{a,c}`, not for applying `shared/`.

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
match is not enough. Four postconditions: the VPC, the provisioning tags, that
the cluster SG is non-empty, and that the cluster's status is `ACTIVE` or
`UPDATING` (`UPDATING` is allowed because a control-plane upgrade reports it for
tens of minutes without changing the SG). The first three have a deliberate
release — `expected_mgmt_vpc_id`, `expected_mgmt_tags = {}`, and
`mgmt_cluster_security_group_id` to skip the lookup entirely. The status guard
has none of its own; skipping the lookup is the only way past it.

That last one releases the first three at once and needs no code change —
`TF_VAR_mgmt_cluster_security_group_id` is enough. So it is `validation`-checked
for the `sg-` format (a typo would otherwise only surface at apply), and
`check "mgmt_guards_engaged"` prints `GUARDS RELEASED` naming every released
guard on every plan. The check covers all three release variables, not just the
override: `TF_VAR_expected_mgmt_tags='{}'` and `TF_VAR_expected_mgmt_vpc_id=...`
widen the same trust boundary and would otherwise produce a plan indistinguishable
from a guarded one. `output "mgmt_guards_released"` carries the same list into
state. It says what is released *right now* — the next normal apply overwrites it
with an empty list, so reconstructing a past break-glass needs state bucket
versioning or CloudTrail.

Releasing the lookup does not mean the value goes unchecked: any non-empty
override is read back with `data "aws_security_group"` and asserted to be in
`expected_mgmt_vpc_id` (the same relocation switch the lookup path honours) and
to carry `aws:eks:cluster-name = mall-apne2-mgmt`. The tag matters more than the
VPC: shared-VPC membership alone would still let the override name any ALB, NLB,
app, or data-layer SG in the region as an ingress source on the workload API
servers. EKS attaches that tag to the SG it manages for a cluster, so the assert
costs break-glass nothing — and an SG read answers whether or not the cluster
itself is still alive, which is the point of the override.

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

Apply the **same value to both spokes**. They are independent variables, so
overriding one and not the other leaves the two AZs behind the same weighted NLB
with different ArgoCD reachability — one syncs, one does not, and the drift is
invisible until a deploy lands unevenly.

A non-empty value is still checked: it must be an SG in `expected_mgmt_vpc_id`
carrying `aws:eks:cluster-name = mall-apne2-mgmt`. If mgmt was rebuilt in a
different VPC, pass `expected_mgmt_vpc_id` too.

Unset it once mgmt is back. Only GitOps reachability is affected — the
CloudFront → NLB → api-gateway traffic path does not use this SG.

**mgmt cluster was renamed.** Two layers, in this order — the spoke lookup needs
the IAM grant for the new name before it can read it:

1. `shared/`: add the new name to `describable_cluster_names` (keep the old one
   for now) and apply. The grant is an ARN-scoped `eks:DescribeCluster`, so
   without this step every spoke plan fails with an access error.
2. `eks-az-a/` and `eks-az-c/`: set `mgmt_cluster_name` to the new name and
   apply both.
3. `shared/`: drop the old name from `describable_cluster_names` and apply.

**Detecting a stale mgmt SG.** Nothing here notices on its own — recreation is
silent until a sync fails. Until there is an alert on the ArgoCD hub's spoke
connection status, or a scheduled drift `plan` on both spokes, this depends on
someone looking.

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
region's `shared/` outputs. These six are **breaking-change-frozen** — renaming
or retyping them breaks that repo's plan:

| Output | Used for |
|--------|----------|
| `vpc_id` | mgmt cluster VPC |
| `private_subnet_ids` | mgmt node placement |
| `alb_security_group_id` | mgmt EKS module argument |
| `nlb_security_group_id` | mgmt EKS module argument |
| `internal_observability_nlb_security_group_id` | spoke → mgmt Tempo/Prometheus ingest |
| `kms_key_arns["s3"]` | mgmt-side Tempo bucket encryption |

The two ALB/NLB SG entries are easy to miss because nothing in this repo reads
them from mgmt's side — they were arguments to the `module "eks"` call in the
deleted `eks-mgmt/` layer, which `AWS-Demo-Platform` now owns as a superset of
what was here. Treat this table as a floor, not a census.

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

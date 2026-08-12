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
One such role was concrete and lives next door: the `ci_runner` role that
`AWS-Demo-Platform` now owns has `AmazonS3FullAccess` (and `ReadOnlyAccess`)
attached and is bound by pod identity to ten runner service accounts — so any CI
workload on the mgmt cluster could read and write this whole state bucket,
including the `shared/` state that carries Aurora and DocumentDB master passwords
in plaintext. Runner pods execute PR code, so that was not a theoretical path.

That one is closed here, with a **bucket policy**:
`terraform/global/terraform-state`, `state_custody_denials`. A resource-policy
Deny beats any Allow in any identity policy, so attaching a managed FullAccess
policy no longer grants it — which is the whole difference between this and a
README warning. The bucket had no policy at all before (`NoSuchBucketPolicy`).
Scope is this repo's state keys plus `global/*` **and** `ci_runner`'s own
`eks-mgmt` key, and it denies non-TLS access. `Principal = "*"` with an
`aws:PrincipalArn` condition naming the denied role directly, not
`NotPrincipal` (fails open when an assumed-role session ARN doesn't match the
role ARN) and not `Principal = { AWS = role-arn }` either (that form pins to
the role's internal principal ID at policy-save time and silently fail-opens
if the role is ever recreated — see the ADR's round-8 note). `ci_runner`'s own
layer key is **not** exempted (round-10 fix — it used to be, on the reasoning
that "that repo owns and applies it"; but per the ADR, `ci_runner` is the
self-hosted GitHub Actions runner role, not the Atlantis identity that
actually applies `infra/eks-mgmt` — repo ownership and this role's own
authorization are different things, and `ci_runner` has no legitimate reason
to touch that key either).

Still outside this: a human with admin credentials, and — concretely, not
theoretically — the same `ci_runner` role can become a *different* principal
ARN via its own `sts:AssumeRole role/cdk-*` and `iam:PassRole role/* (ecs-tasks)`
+ `ecs:RunTask` grants (both owned by the other repo), neither of which this
Deny's `aws:PrincipalArn` condition matches. Custody is closed for calls made
as `ci_runner` itself; it is not closed against that pivot. See the ADR
follow-up for what's tracked and where.
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
in `ap-northeast-2`. `describable_cluster_names` is derived from
`mgmt_cluster_name` (`[var.mgmt_cluster_name]`), not a second hardcoded list
(round-9 fix — it used to be a literal that could drift from `mgmt_cluster_name`
independently), so a rename's IAM grant and its output value change together in
the same `shared/` apply. See the rename runbook below for the two-phase
procedure this is still part of.

That SG becomes an ingress trust boundary on the workload API servers, so a
name-only match is not enough. **Four** `postcondition`s guard the lookup: the
cluster must sit in this region's shared VPC, it must carry this platform's
`ManagedBy=terraform` / `Project=multi-region-mall` tags, it must actually report
a cluster SG (empty would make the EKS module drop the ingress rule silently),
and its status must be `ACTIVE` or `UPDATING` (`UPDATING` is allowed because a
control-plane upgrade reports it for tens of minutes without changing the SG,
and rejecting it would fail every plan here during routine external
maintenance). The override path adds two more of its own, below.

The first three have a deliberate release — `expected_mgmt_vpc_id`,
`expected_mgmt_tags = {}`, and the break-glass override to skip the lookup
entirely. The status guard has none of its own; skipping the lookup is the only
way past it.

All of it lives in `terraform/modules/security/mgmt-cluster-trust`, called by
both spokes. It is a module rather than two copies because guard drift between
the AZs would otherwise be invisible in review — the wrong failure mode for the
code deciding who may reach an API server.

**All five trust inputs live in `shared/`**, not in the spokes:
`mgmt_cluster_name`, `default_mgmt_cluster_name` (the rename baseline
`mgmt_cluster_name` is compared against — added in round-8, see below),
`expected_mgmt_vpc_id`, `expected_mgmt_tags`, and the break-glass override.
Each of them decides who may reach a workload API server
and each is releasable from the environment with a `TF_VAR_*`; as per-spoke
variables they shared one failure mode — release the guard on az-a, forget az-c,
and the two clusters behind one weighted NLB over one Aurora/DocumentDB primary
end up with different ArgoCD reachability, so a schema migration reaches half the
fleet.

What that buys is exactly one thing: the two spokes cannot be asked to trust
*different* values. It does **not** make them converge — each still needs its own
apply, so a one-sided window exists between the two. `scripts/check-mgmt-guards.sh`
is what closes it: it fails if either spoke has a released guard, if the two
spokes' `mgmt_guards_released` differ (= only one was applied), if the two
spokes' resolved `mgmt_trust_security_group_id` differ (guards can converge to
`[]` on both sides while the *SG they actually trust* has diverged — e.g. mgmt
was replaced and only one spoke re-applied), if either spoke is uninitialized,
and if `argocd cluster list` does not show both spokes `Successful` — a missing
CLI, a failed command, or a non-`Successful` status all fail the check rather
than being swallowed. That script is also the answer to "`check` only warns" —
a `check` block by definition cannot fail a plan, and this turns that warning
into an exit code. It is run by hand: there is no terraform CI apply path in
this repo, and standing scheduled automation against production is not
something a review finding gets to introduce.

That last one releases the first three at once and needs no code change. So it
is `validation`-checked for the `sg-` format (a typo would otherwise only surface
at apply), and `check "mgmt_guards_engaged"` prints `GUARDS RELEASED` naming
every released guard on every plan. The check covers four of the five trust
inputs directly, not just the override: `expected_mgmt_tags`,
`expected_mgmt_vpc_id`, and `mgmt_cluster_name` widen the same boundary and
would otherwise produce a plan indistinguishable from a guarded one.
`mgmt_cluster_name` is in there because it is a trust input, not just a label —
the override asserts the SG carries this cluster's ownership tag, so override +
name together would authorize some other cluster's SG. It's compared against
the fifth input, `default_mgmt_cluster_name` — but that comparison is the only
role `default_mgmt_cluster_name` plays here; there is deliberately no separate
check on it drifting from *its own* reviewed default. An earlier version of
this guard tried that (comparing it against the module's hardcoded
`"mall-apne2-mgmt"` literal, to catch someone moving both trust inputs to the
same new value in one shot instead of via the runbook below) and it made every
*legitimate* completed rename report permanently "released" from then on —
state alone can't tell "both values landed on the same name because the
runbook was followed in two applies" apart from "both landed on the same name
in one apply", so a check trying to catch the latter necessarily also flags
the former forever. Removed rather than left broken; see the ADR's
Consequences for the reasoning. `output "mgmt_guards_released"` carries the same list
into state. It says what is released *right now* — the next normal apply
overwrites it with an empty list, so reconstructing a past break-glass needs
state bucket versioning or CloudTrail.

Releasing the lookup does not mean the value goes unchecked: any non-empty
override is read back with `data "aws_security_group"` and asserted to be in
this region's shared VPC — always, regardless of whether `expected_mgmt_vpc_id`
is released (round-9 fix: anchoring the override to that *releasable* variable
meant one `shared/` edit widening it would silently widen what the override
accepts too, defeating both guards with a single flag) — and to
carry `kubernetes.io/cluster/<mgmt_cluster_name> = owned`. The tag matters more
than the VPC: shared-VPC membership alone would still let the override name any
ALB, NLB, app, or data-layer SG in the region as an ingress source on the workload
API servers. EKS attaches that tag to the SG it manages for a cluster, so the
assert costs break-glass nothing — and an SG read answers whether or not the
cluster itself is still alive, which is the point of the override.

Not `aws:eks:cluster-name`, which EKS also attaches and which reads better: the
AWS provider strips `aws:`-prefixed system tags out of every data source's `tags`
map, so that key is always absent and the assert would fail for *every* SG — i.e.
the guard would only ever fire during the incident it exists to survive. Measured
against the live mgmt cluster SG on provider 6.52.0: `DescribeSecurityGroups`
returns four tags including `aws:eks:cluster-name`, Terraform surfaces three and
drops exactly that one.

## Runbooks

**mgmt cluster was recreated (SG ID changed).** Workloads keep serving — only
GitOps sync breaks, and only at the next sync, so this fails quietly:

1. `AWS-Demo-Platform` applies `infra/eks-mgmt`.
2. Here: `terraform apply` in **both** `eks-az-a/` and `eks-az-c/`.
3. On mgmt: `argocd cluster list` shows both spokes `Successful`.
4. `bash scripts/check-mgmt-guards.sh` — confirms both spokes converged (their
   `mgmt_guards_released` match) and no guard is left released.

**mgmt is down / moved / `eks:DescribeCluster` fails and you must apply a spoke.**
The live lookup makes mgmt a plan-time dependency, so set
`mgmt_cluster_security_group_id_override` in **`shared/`** — any non-null value
drops the spoke data source's `count` to 0, removing both the API read and its
postconditions. There is no such variable on a spoke root: passing
`-var mgmt_cluster_security_group_id=...` to `eks-az-a` errors out immediately.
`shared/` is the single source and both spokes read it from that layer's state,
because overriding one AZ and forgetting the other leaves the two clusters behind
the same weighted NLB, over the same Aurora/DocumentDB primary, with different
ArgoCD reachability — one syncs, one does not, and a schema migration reaches half
the fleet.

Three applies, and the value goes in `terraform.tfvars` rather than on the command
line: passed with `-var`, the next unrelated `shared/` apply silently reverts it to
`null` and erases the `released_guards` trace with it — and `shared/` is the
foundation layer, so that apply is a routine one.

```bash
# 1. shared/ — commit the value, then apply
cd shared
# keep the ArgoCD ingress rule, using the SG ID you already know:
#   mgmt_cluster_security_group_id_override = "sg-0123456789abcdef0"
# ...or drop the rule entirely — the EKS module skips it on "":
#   mgmt_cluster_security_group_id_override = ""
$EDITOR terraform.tfvars
terraform plan    # expect ONE output change and nothing else — this layer holds
                  # Aurora/DocumentDB/MSK, so read the plan before applying
terraform apply

# 2. both spokes pick it up (order does not matter, but do both)
(cd ../eks-az-a && terraform apply)
(cd ../eks-az-c && terraform apply)

# 3. verify both actually moved
bash ../../../../../scripts/check-mgmt-guards.sh --expect-released
```

Use `--expect-released` here, not the plain form. Plain `check-mgmt-guards.sh`
FAILs on a released guard and on `argocd cluster list` not showing both spokes
`Successful` — both of which are *expected* right now (that's the whole point
of break-glass), so the plain form would exit non-zero on every legitimate
use of this runbook, training whoever runs it to ignore the exit code
entirely (round-9 review L4 MAJOR). `--expect-released` prints those two as
`INFO` instead of `FAIL` and keeps the exit code driven only by what actually
still matters here: do the two spokes agree with each other (`mgmt_guards_released`,
`mgmt_trust_security_group_id`) **and** with what `shared/` currently declares —
i.e. did both spokes actually pick up the value you just committed, not just
converge on some older one. A non-zero exit from the `--expect-released` run
means the spokes have not converged on the override; a zero exit does not mean
mgmt is healthy, only that both spokes are consistently pointed at the value
you intended.

`""` has a real cost worth calling out explicitly: it does not just release a
guard, it removes the ArgoCD ingress rule entirely, and that rule is what the
ADR calls the rollback channel during this exact kind of incident. There is no
alternate rollback route documented here (bastion `kubectl`/`argocd`, a
temporary CIDR-based ingress rule) — until one exists, `""` should be treated
as the last resort after "do we actually know an SG ID" has been ruled out,
not a default first move, and whoever runs it should have another way to
reach the API servers already in mind before they do.

That the break-glass value sits in the foundation layer is a real cost — an
ArgoCD ingress rule should not need a plan that includes the data stores. It is
still the lesser failure: a per-spoke variable makes "released on one AZ only"
reachable, and that one is silent. Mitigation is procedural — read the plan and
confirm the only change is the output.

A non-empty value is still checked: it must be an SG in this region's shared
VPC (always — the override does not honour `expected_mgmt_vpc_id`, round-9 fix;
see the override section above) carrying `kubernetes.io/cluster/<mgmt_cluster_name>
= owned`. If mgmt was permanently rebuilt in a different VPC, that's the
live-lookup path's job, not the override's: set `expected_mgmt_vpc_id` in
`shared/` and let the spokes look mgmt up live instead of naming an override SG.
Note also that SG-reference ingress needs a peering connection or the same VPC —
it does not work over Transit Gateway at all, regardless of TGW security group
referencing settings, so if mgmt moves to a VPC reachable only via TGW the
option is `""` plus a different GitOps route.

Unset it once mgmt is back, apply all three again, and re-run
`scripts/check-mgmt-guards.sh` — the guards should report clean. Only GitOps
reachability is affected throughout; the CloudFront → NLB → api-gateway traffic
path does not use this SG.

**mgmt cluster was renamed.** Two phases, in this order:

1. `shared/`: set `mgmt_cluster_name` to the new name and apply. Because
   `describable_cluster_names` is derived from that same variable, this one
   apply grants `eks:DescribeCluster` on the new name **and** updates the
   output both spokes read, atomically — no separate "add the new name first"
   step is needed anymore (round-9 fix; it used to be a second hardcoded list
   that had to be edited in its own step, in order, before this one). Apply
   both `eks-az-a/` and `eks-az-c/` so they pick up the new name. Expect
   `mgmt_guards_released` to report `mgmt_cluster_name` as released on both
   spokes at this point — that's correct: it's compared against
   `default_mgmt_cluster_name`, which hasn't moved yet, so this is the
   in-progress signal, not a problem.
2. **Once both spokes have converged on the new name** (both applies in step 1
   succeeded — confirm with `bash scripts/check-mgmt-guards.sh --expect-released`,
   *not* the plain form: the `mgmt_cluster_name` guard is released on both right
   now by design, and plain mode FAILs on any released guard regardless of
   whether that's expected — `--expect-released` reports it as INFO instead and
   still hard-fails on the thing that actually matters here, the two spokes not
   agreeing with each other):
   `shared/` sets `default_mgmt_cluster_name` to the same new name and applies,
   then both spokes apply once more to pick up the new baseline. Skipping this
   step leaves the `mgmt_cluster_name` guard permanently "released" — the module compares the
   new name against the *old* baseline forever, so `check-mgmt-guards.sh` fails
   from here on even though nothing is actually released anymore. This must be
   the last step, run only once both spokes have actually converged on the new
   name from step 1 — there is no automated check for doing this out of order
   (a prior attempt at one turned out to be unfixable from state alone, see the
   ADR's Consequences), so treat "both spokes converged" as a precondition you
   confirm yourself before running this step, not something the tooling
   enforces for you.

**Detecting a stale mgmt SG.** Nothing here notices on its own — recreation is
silent until a sync fails, and during an incident that sync is the rollback
channel. A `terraform plan -detailed-exitcode` in either spoke surfaces it (the
SG is resolved live, so a replaced cluster shows as a diff on the API-server
ingress rule), but nothing runs that on a schedule. `bash scripts/check-mgmt-guards.sh`
packages the check into one command — guard state on both spokes, whether the two
converged, and `argocd cluster list` for real reachability — so it is the thing to
run after any mgmt change and after any break-glass. Continuous detection (an
ArgoCD hub-side spoke-connection alert or a scheduled drift plan) is still open
and tracked as follow-up in the ADR; standing production automation is a separate
decision, not something this handoff introduces.

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

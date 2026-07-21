# Portability Assessment

Can this repo be deployed as-is into a different AWS account/environment? **No — not without manual work.** This document catalogs what's already parameterized, what's hardcoded but fixable, and what's fundamentally non-portable (needs recreating out-of-band), plus a live-incident log of gaps this repo's own documentation didn't know about. Written 2026-07-21 after a mall.atomai.click outage/recovery that surfaced most of the findings below.

## Summary verdict

The Terraform/K8s *code* is close to portable for the data-plane (VPC, data stores, compute) — most modules take proper variables. What isn't portable:

1. **The account ID is hardcoded in ~70+ files** (K8s deployment images, IRSA annotations, ArgoCD appsets) — a fresh account needs a repo-wide find/replace, not a variable change.
2. **Live coordination between two separate GitOps repos.** The ArgoCD *ApplicationSets themselves* (which infra components exist, at all) are managed from a different, shared repo (`AWS-Demo-Platform`), not this one — see [The dual-repo GitOps split](#the-dual-repo-gitops-split-discovered-live). A fresh account needs that layer rebuilt too, and this repo's own docs never mentioned it exists.
3. **Post-deploy values fed back into pre-deploy config** (NLB DNS names, target group hex IDs, security group IDs) — a two-pass bootstrap, not a single `terraform apply`.
4. **A cross-region data dependency the code and docs both deny exists** — Korea's DocumentDB is a live global-cluster secondary of us-east-1's primary. See [DocumentDB global-cluster drift](#documentdb-global-cluster-drift).
5. Domain, ACM certs, and one cross-account Bedrock ARN must be manually arranged per account.

## Already parameterized (portable as-is)

- `scripts/build-and-push.sh`, `scripts/seed-data/build-and-push-seed.sh`, `scripts/backup-restore/build-and-push.sh` — take `AWS_ACCOUNT_ID`/`AWS_REGION` env vars.
- GitHub Actions workflows — use `${{ secrets.AWS_ACCOUNT_ID }}`.
- Terraform modules under `terraform/modules/` — take proper input variables (region, environment, VPC ID, subnet IDs, KMS ARNs, etc.).
- Karpenter `EC2NodeClass` — discovers subnets/SGs by tag, not hardcoded ID.
- Frontend (`src/frontend/src/api.js`) — calls a relative `/api/v1` path, no hardcoded host.

## Hardcoded but mechanically fixable

| What | Where | Fix |
|---|---|---|
| Real AWS account ID (`180294183052`) | ~20 `k8s/services/*/deployment.yaml` (ECR image + IRSA annotations), ~50 `k8s/infra/argocd*/apps/*.yaml` (ECR image, IRSA role ARNs) | Repo-wide substitution keyed off one variable; no templating exists today |
| Terraform S3 backend bucket/table name | ~13 `backend.tf` + matching `terraform_remote_state` data sources | S3 bucket names are globally unique — needs renaming in every environment before `terraform init` will even work in a new account |
| Literal `<YOUR_PASSWORD>` master passwords | `terraform/modules/data/aurora-global/main.tf:52`, `documentdb-global/main.tf`, `opensearch/variables.tf` default | `terraform apply` will *literally* set this as the password — replace before any real deploy |
| `scripts/deploy-frontend.sh` absolute path (`/home/ec2-user/...`) and hardcoded CloudFront distribution ID / us-east-1 bucket | `scripts/deploy-frontend.sh` | Needs the same "which region/distribution am I deploying to" parameterization CloudFront itself now needs post-incident (see below) |
| GitOps `repoURL` inconsistency: some ApplicationSets use `git@github.com:...git` (SSH), others `https://github.com/...` | Most of `k8s/infra/argocd-korea/apps/*.yaml` use SSH; the two that are actually live (`workloads-apne2-az-{a,c}`) use HTTPS | ArgoCD in this account only has HTTPS credentials registered — every SSH-form appset is untested/likely broken; standardize on HTTPS |

## Fundamentally non-portable (manual per-account setup)

- **Domain + Route53 hosted zone** (`atomai.click`) — must be owned and delegated per account.
- **ACM certificates** — never created by Terraform in this repo (no `aws_acm_certificate` resource in any environment); must be issued + DNS-validated manually. CloudFront specifically needs its cert in **us-east-1** regardless of which region the distribution serves.
- **Post-deploy values baked into pre-deploy config** — NLB DNS names (`prod-api-nlb-apne2-*.elb...`), target group ARN hex suffixes, and several `sg-*`/`subnet-*` literals in `k8s/overlays/*/platform/kustomization.yaml` and ArgoCD manifests are AWS-generated after the first deploy, then hand-pasted back into config. A fresh account needs: apply infra → read the generated IDs → patch config → apply again.
- **Cross-account Bedrock inference profile** (`arn:aws:bedrock:ap-northeast-2:013503698282:inference-profile/...`) in `terraform/modules/security/iam` callers — points at a *different* AWS account entirely; presumably a shared org resource, not something a new account can reuse.
- **ECR images** — all 20 service images + the two ops images (`seed-data`, `backup-restore`) must be rebuilt and pushed to the new account's registry before any pod will actually start.

## The dual-repo GitOps split (discovered live)

This repo's own docs (CLAUDE.md, `k8s/infra/argocd-korea/README` if it existed) describe `k8s/infra/argocd-korea/apps/*.yaml` as *the* source of truth for what's deployed on the Korea clusters. **That's only true for the two "workload" Applications** (`workloads-apne2-az-a`, `workloads-apne2-az-c`, which apply `k8s/overlays/...`). Every platform/system-tier ApplicationSet in that same directory (ALB controller, External Secrets, Karpenter, ClickHouse, Istio, …) is **not** what mgmt's ArgoCD actually watches.

The real source for those is `master-system-root`, an Application on `mall-apne2-mgmt` pointed at a *different* GitHub repo — `AWS-Demo-Platform`, path `argocd-apps/system` — which is the shared platform repo for this AWS account's several unrelated tenants (this mall, `ai-trader-web`, `ttobak`, `aws-fsi-demo`, and others). Files with matching names exist in both repos, but only `AWS-Demo-Platform`'s copies are live; `multi-region-architecture`'s copies are effectively a public-safe **mirror/sample**, not the deployment source.

Two incidents this session were caused directly by this split:
- `k8s/infra/argocd-korea/apps/appset-helm-alb-controller.yaml` had a roleArn typo, fixed in this repo — with zero effect, because ArgoCD never reads it. The real fix had to go into `AWS-Demo-Platform#74`.
- A new ApplicationSet added here to wire up External Secrets CRs (`appset-external-secrets-crs.yaml`) likewise did nothing until mirrored into `AWS-Demo-Platform` (`#77`, `#78`).

**Implication for portability**: standing up this mall in a fresh account requires *also* recreating whatever `AWS-Demo-Platform`'s `argocd-apps/system` currently provides for it (ALB controller, External Secrets operator + CRs, Karpenter, ClickHouse, storageclass) — none of which ships from this repo alone. If the new account won't have an `AWS-Demo-Platform`-equivalent shared platform repo, every one of those appsets needs a real home inside `multi-region-architecture` itself, wired to an app-of-apps this repo actually owns.

## DocumentDB global-cluster drift

CLAUDE.md and this repo's Terraform both assert Korea's DocumentDB is an **independent primary** ("Korea does NOT share global clusters with the US... Korea DocumentDB: is_primary = true... NOT a global cluster secondary"). Live AWS state says otherwise:

```
aws docdb describe-global-clusters
→ GlobalClusterIdentifier: multi-region-mall-docdb
  Members:
    production-docdb-global-primary (us-east-1)         IsWriter: true
      Readers: [production-docdb-global-ap-northeast-2]
    production-docdb-global-ap-northeast-2 (ap-northeast-2)  IsWriter: false
```

Korea's cluster is a live, actively-replicating **secondary** of the us-east-1 primary, over the global cluster `multi-region-mall-docdb`. Consequences discovered mid-incident:

- `aws docdb modify-db-cluster --master-user-password ...` on the Korea cluster fails outright: `Cannot modify the master password for secondary clusters`. Password rotation has to happen on the **us-east-1 primary**; it replicates down automatically (confirmed — rotating on us-east-1 fixed auth on Korea within ~8 minutes).
- Korea's DocumentDB is **read-only**. This happens to match how the app already connects (`readPreference=secondaryPreferred`), so it "works" — but any doc claiming Korea can independently operate its own DocumentDB writer is wrong today.
- us-east-1's EKS/compute/CloudFront are fully decommissioned, but this *one* piece of us-east-1 (`production-docdb-global-primary`) is still alive and load-bearing for Korea. Anyone tearing down "the rest of us-east-1" would break Korea's DocumentDB auth without any obvious link between the two.

**For a portability exercise**: a truly independent Korea deployment needs this global-cluster membership actually removed (promote Korea to a standalone primary, or accept the us-east-1 dependency as permanent and document it that way — the current state does neither).

## Live-incident findings not specific to portability, but relevant to "is the code trustworthy"

These were found while restoring `mall.atomai.click` (site fully down: dead CloudFront distribution, `az-a` NLB targets unhealthy, product-catalog unable to authenticate to DocumentDB). Not portability issues per se, but proof that several code paths in this repo had never actually been exercised end-to-end:

- **`terraform/modules/edge/cloudfront`** had an `origin_shield { enabled = false }` block with no region set. The current AWS provider rejects this (`MalformedXML`) even when disabled — `module.cloudfront` could not create *any* distribution, in any environment, until this was removed. (Fixed.)
- **No S3 bucket policy or KMS key policy ever granted the CloudFront OAC access** to the static-assets bucket/key — `module "cloudfront"` only creates the `aws_cloudfront_origin_access_control` object, nothing authorizes it. Every S3-origin request would 403. us-east-1's original call has the identical gap. (Fixed for Korea; us-east-1 not touched, since it's decommissioned.)
- **`k8s/infra/external-secrets/`** (ClusterSecretStore + all `ExternalSecret` CRs) was never applied by any ArgoCD Application, on either region — only the operator's own Helm chart was. Zero `ClusterSecretStore`/`ExternalSecret` objects existed. Every service depending on `envFrom: secretRef` for its DB credentials was silently running with no credentials at all (`optional: true` on the secretRef swallows the absence).
- Even after wiring that up, `core-services.yaml`'s `product-catalog-secrets` `ExternalSecret` mapped Secrets Manager's `password` property to a K8s secret key named `DOCUMENTDB_PASSWORD` — but `mall_common/config.py`'s `ServiceConfig` reads `DB_PASSWORD` (no `documentdb_password` field exists at all). The mismatched key was silently ignored, so the app's Mongo client always built a **no-auth, no-TLS** connection string against a TLS-only port — which doesn't fail fast, it hangs until the driver's connect timeout.
- Korea's `k8s/overlays/ap-northeast-2-az-{a,c}/kustomization.yaml` had `zzzzzzzzzzzz`-style template placeholders for Aurora/DocumentDB/ElastiCache/MSK/OpenSearch endpoints — and a few base identifiers were wrong outright (`production-docdb-ap-northeast-2-az-a` instead of the real `production-docdb-global-ap-northeast-2-1`). These had clearly never been filled in with live values.
- `az-a`/`az-c` ALB controllers had `roleArn`s pointing at IAM roles (`production-alb-controller-apne2-az-{a,c}`) that don't exist; the correct roles (`mall-apne2-az-{a,c}-alb-controller-apne2-az-{a,c}`) already existed and were already used correctly for `mgmt`. The mismatch meant target-group health checks silently failed with `AssumeRoleWithWebIdentity` 403 — traffic still theoretically flowed (existing stale registrations), until pods rescheduled and target IPs drifted.
- A node group (`mall-apne2-az-c-bootstrap`) was stuck `DEGRADED` and refusing its 1.35→1.36 upgrade because its underlying ASG's `VPCZoneIdentifier` had drifted to the **data** subnets instead of the **private** subnets EKS expected — not an IP-capacity problem, a subnet-identity mismatch (data subnets are `/24`s with far less headroom, which is what made it *look* like an IP shortage).

None of these would show up in `terraform plan`/`validate` — they're all runtime-only failures (API rejects a specific field shape, a policy that's silently absent, a key name that's silently ignored). `scripts/test-traffic-flow.sh` also didn't catch most of this: it's hardcoded to check `us-east-1`/`us-west-2` NLBs and sanitized example security-group IDs from CLAUDE.md, and doesn't check Korea at all.

## Data migration

Code alone can't reproduce a deployment's *data*. `scripts/backup-restore/` (added alongside this report) covers what `scripts/seed-data/` can't regenerate — Aurora (`pg_dump`), DocumentDB (`mongodump`), and S3 product images. Valkey/MSK/OpenSearch are intentionally excluded; re-seed those on the target with the existing `scripts/seed-data/` scripts instead. See that directory's own docs for usage. Known gap: Aurora backup needs a `mall/core/aurora` Secrets Manager entry that doesn't exist yet (only `mall/core/documentdb` and `mall/shared/msk` were populated, enough to unblock the specific incident this was written during).

## New-account bootstrap order (if attempting this despite the above)

1. Register/delegate a domain; issue ACM certs (remember: CloudFront's cert must be in us-east-1 regardless of serving region).
2. Create the Terraform state S3 bucket + lock table under new, globally-unique names; update every `backend.tf`.
3. Decide the DocumentDB global-cluster question above — don't silently inherit the current Korea-depends-on-us-east-1 reality without documenting it.
4. `terraform apply` global → shared → eks-* layers, per region.
5. Build and push all 20 service images + `seed-data` + `backup-restore` to the new account's ECR.
6. Stand up (or point at an existing) platform-tier ArgoCD app-of-apps for ALB controller / External Secrets / Karpenter CRs / etc. — this repo alone does not provide it (see the dual-repo section).
7. First real deploy will produce NLB DNS names, target-group ARNs, and security-group IDs — feed those back into the overlay `kustomization.yaml`s and re-apply (the two-pass bootstrap).
8. Populate Secrets Manager under the `mall/*` naming convention `k8s/infra/external-secrets/secrets/*.yaml` expects — none of it is created by Terraform today.
9. Run `scripts/backup-restore/restore.sh` against a source environment's archive, then `scripts/seed-data/run-seed.sh` for Valkey/MSK/OpenSearch.
10. Verify with `curl` against the real hostname end-to-end — `scripts/test-traffic-flow.sh` is stale (checks decommissioned us-east-1/us-west-2, sanitized example SG IDs) and won't catch most of what actually breaks.

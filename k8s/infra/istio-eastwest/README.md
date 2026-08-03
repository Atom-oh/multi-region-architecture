# Istio Ambient — Korea zone failover (az-a ↔ az-c)

## What this buys you

Korea's az-a and az-c are two **independent, full-copy** EKS clusters (see
root `CLAUDE.md` → Korea Region). Zone failover already exists for the
*north-south* path: the shared multi-AZ NLB (`prod-api-nlb-apne2`) is
weighted 50/50 across both clusters' target groups and stops sending traffic
to an unhealthy one.

What was missing: *east-west* failover. `api-gateway` only ever calls
`payment.core-services.svc.cluster.local` — its own cluster. If az-a's
`payment` pods all crash but az-a's `api-gateway` is fine, that AZ's payment
requests fail even though az-c's `payment` is healthy right next door.

Istio ambient multicluster (beta since 1.29) fixes exactly this: ztunnel in
each cluster learns endpoints for any Service labeled `istio.io/global` in
**both** clusters, prefers local ones, and fails over to the remote cluster
via the east-west gateway when local endpoints are unhealthy — no
application code changes.

## What's installed (via ArgoCD, `k8s/infra/argocd-korea/apps/`)

This repo is a self-contained deployable unit: registering
`k8s/infra/argocd-korea/apps/root-app.yaml` in any ArgoCD app-of-apps pulls
in everything below automatically. **Caveat for the current live account**:
platform-tier ApplicationSets are actually watched from the
`AWS-Demo-Platform` hub repo, not from here — see
`docs/portability-assessment.md` ("dual-repo GitOps split"). In that
environment these Istio appsets must also be mirrored into the hub's
`argocd-apps/system/` to take effect.

| Component | ApplicationSet | Source | Namespace |
|---|---|---|---|
| `base` (Istio CRDs) | `appset-helm-istio-base.yaml` | Istio Helm repo 1.30.1 | `istio-system` |
| `cni` (ambient node agent, DaemonSet) | `appset-helm-istio-cni.yaml` | Istio Helm repo | `istio-system` |
| `istiod` (+ `AMBIENT_ENABLE_MULTI_NETWORK`/`BAGGAGE` env) | `appset-helm-istiod.yaml` | Istio Helm repo | `istio-system` |
| `ztunnel` (per-node proxy, + multiCluster/network values) | `appset-helm-ztunnel.yaml` | Istio Helm repo | `istio-system` |
| Gateway API CRDs + east-west `Gateway` (HBONE 15008) | `appset-istio-eastwest.yaml` | this repo: `k8s/infra/istio-eastwest/` | `istio-system` |

Deployed to az-a and az-c only — **mgmt is excluded** (observability/ArgoCD/
runners only, no mesh membership needed).

### Why a Gateway API resource, not the helm `gateway` chart

Ambient multicluster does not use the legacy sidecar-style east-west gateway
(`ISTIO_META_ROUTER_MODE=sni-dnat` + `AUTO_PASSTHROUGH`). The 1.29+ model is
a `gateway.networking.k8s.io/v1` Gateway with `gatewayClassName:
istio-east-west` and a single HBONE listener on 15008 (`ISTIO_MUTUAL`,
double-HBONE). Istio auto-deploys the Service/Deployment for it and copies
the Gateway's annotations onto the generated Service — which is how the
internal-NLB scheme and the Terraform-managed SG
(`sg-0355c4a665545ff7d`, from `terraform output
istio_eastwest_security_group_id`, ports 15008–15021, VPC-CIDR only, never
`0.0.0.0/0`) get applied.

Mesh identity: shared `meshID: vellure-mesh-kr`, distinct `network` per
cluster (`az-a`/`az-c`) — ambient multicluster only supports the
multi-network model even though both clusters share one VPC (`10.2.0.0/16`),
so cross-cluster traffic always crosses via the east-west gateways.

## Pilot scope

Only `payment` and `order` Services (`k8s/overlays/ap-northeast-2-az-{a,c}/
core/kustomization.yaml`) are labeled `istio.io/global: "true"` today —
deliberately narrow so failover behavior can be validated before widening.
To add a service, add the same patch for its Service in both AZ overlays.

Deliberately not done yet (add when the pilot proves out):
- No waypoint proxies — ztunnel L4 failover only; add a waypoint when L7
  retry/outlier-detection tuning is needed.
- No mesh-wide rollout — 2 pilot services only.

## Bootstrap steps that can't be GitOps'd (run once, in this order)

### 1. Shared root of trust (cacerts) — BEFORE istiod starts

Without a common root CA, each istiod self-signs its own CA: discovery works
but cross-cluster HBONE mTLS is untrusted and **failover never actually
happens**. Generate a root CA + per-cluster intermediates and create the
`cacerts` secret on both clusters:

```bash
bash scripts/istio-cacerts.sh
# store the printed root-key.pem in Secrets Manager, delete the local copy
```

If istiod was already running, restart it afterwards
(`kubectl rollout restart deployment/istiod -n istio-system --context <ctx>`).

### 2. Remote secrets — cross-cluster API discovery

```bash
istioctl create-remote-secret --context=mall-apne2-az-a --name=mall-apne2-az-a \
  | kubectl apply -f - --context mall-apne2-az-c

istioctl create-remote-secret --context=mall-apne2-az-c --name=mall-apne2-az-c \
  | kubectl apply -f - --context mall-apne2-az-a
```

To rotate later, just re-run both commands — don't hand-edit the secrets.

## Verification

1. `bash scripts/test-traffic-flow.sh` — north-south path + SG audit intact.
2. Components healthy on both clusters:
   ```bash
   kubectl get pods -n istio-system --context mall-apne2-az-a
   kubectl get gateway istio-eastwestgateway -n istio-system --context mall-apne2-az-a
   ```
3. Cross-cluster endpoints visible (pod IPs from both AZs for `payment`):
   ```bash
   istioctl zc workloads --context mall-apne2-az-a | grep payment
   ```
4. **Failover test** — kill az-a's payment, confirm az-a still serves the
   payment path (via az-c):
   ```bash
   kubectl scale deployment/payment -n core-services --replicas=0 \
     --context mall-apne2-az-a
   # exercise a REAL payment call through mall-kr.atomai.click (not just
   # /health) and check OTel/Grafana traces for the cross-AZ hop
   # (availability_zone=ap-northeast-2c on a request that entered az-a)
   kubectl scale deployment/payment -n core-services --replicas=<original> \
     --context mall-apne2-az-a
   ```
5. **Duplicate-payment check**: payment/order are the most write- and
   money-sensitive services in the mesh. During the failover window, verify
   in Aurora that no order/payment row was processed twice (idempotency-key
   uniqueness holds). If duplicates appear, gate cross-AZ failover behind a
   waypoint with retry budget — or move the pilot to read-heavy services
   (product-catalog, search) first.
6. Steady-state: cross-AZ trace volume ≈ 0 (ambient prefers local endpoints).

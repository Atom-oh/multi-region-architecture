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

Istio ambient (multicluster, GA beta since 1.29) fixes exactly this: pods in
each cluster's ztunnel get endpoints for any Service labeled
`istio.io/global` in **both** clusters, and route to the local one first,
falling over to the remote cluster's endpoints when local ones are
unhealthy — without touching application code.

## What's installed (via ArgoCD, `k8s/infra/argocd-korea/apps/`)

This repo is a self-contained deployable unit: registering
`k8s/infra/argocd-korea/apps/root-app.yaml` in any ArgoCD app-of-apps pulls
in everything below automatically (the `apps/` kustomization indexes all of
it — workloads and project infra alike).

| Chart/manifest | ApplicationSet | Source | Namespace |
|---|---|---|---|
| `base` (CRDs) | `appset-helm-istio-base.yaml` | Istio Helm repo | `istio-system` |
| `cni` (ambient node agent, DaemonSet) | `appset-helm-istio-cni.yaml` | Istio Helm repo | `istio-system` |
| `istiod` | `appset-helm-istiod.yaml` | Istio Helm repo | `istio-system` |
| `ztunnel` (per-node proxy, DaemonSet) | `appset-helm-ztunnel.yaml` | Istio Helm repo | `istio-system` |
| `gateway` as `eastwestgateway` (internal NLB) | `appset-helm-istio-eastwest-gateway.yaml` | Istio Helm repo | `istio-system` |
| `cross-network-gateway` (Gateway CR, SNI passthrough on 15008) | `appset-istio-eastwest.yaml` | this repo: `k8s/infra/istio-eastwest/cross-network-gateway.yaml` | `istio-system` |

Deployed to az-a and az-c only — **mgmt is excluded** (observability/ArgoCD/
runners only, no mesh membership needed).

Mesh identity: shared `meshID: vellure-mesh-kr` and trust domain (so mTLS
between clusters is trusted), distinct `network` per cluster (`az-a`/`az-c`)
— ambient multicluster only supports the multi-network model even though
both clusters share one VPC (`10.2.0.0/16`), so traffic always crosses via
the east-west gateways rather than pod IP directly.

Networking: the east-west gateway is an **internal** NLB restricted to the
Terraform-managed `istio_eastwest` security group
(`terraform/modules/networking/security-groups/main.tf` →
`aws_security_group.istio_eastwest`, ports 15008/15012/15017, VPC-CIDR only —
never `0.0.0.0/0`, per `CLAUDE.md`). Get the real SG ID with:

```bash
cd terraform/environments/production/ap-northeast-2/shared
terraform output istio_eastwest_security_group_id
```

...and update the placeholder in
`k8s/infra/argocd-korea/apps/appset-helm-istio-eastwest-gateway.yaml`
(`serviceAnnotations` → `aws-load-balancer-security-groups`) before applying.

## Pilot scope

Only `payment` and `order` Services (`k8s/overlays/ap-northeast-2-az-{a,c}/
core/kustomization.yaml`) are labeled `istio.io/global: "true"` today —
deliberately narrow so the failover behavior can be validated on two
services before opening it up to the rest of core/user/fulfillment/business.
To add a service to the mesh-global set, add the same two-line patch
(`op: add, path: /metadata/labels, value: {istio.io/global: "true"}`) for its
Service in both az-a and az-c's overlay.

Not done, on purpose (ponytail: add when the pilot proves out):
- No waypoint proxies — L4 failover via ztunnel is enough for the current
  goal; add a waypoint only if L7 retry/outlier-detection tuning is needed.
- No mesh-wide rollout — only 2 pilot services are global.

## The one step that isn't GitOps'd: remote secrets

For each istiod to discover the *other* cluster's Services/Endpoints, it
needs a `Secret` containing a kubeconfig for the peer's API server, labeled
`istio/multiCluster: "true"`. This can't be templated in git — it's a live
credential — so run it manually once per direction after both clusters'
istiod are up:

```bash
# From a machine with both kubectl contexts configured
istioctl create-remote-secret --context=mall-apne2-az-a --name=mall-apne2-az-a \
  | kubectl apply -f - --context mall-apne2-az-c

istioctl create-remote-secret --context=mall-apne2-az-c --name=mall-apne2-az-c \
  | kubectl apply -f - --context mall-apne2-az-a
```

If istiod's remote-cluster credentials ever need rotating, follow
`aws-core:aws-secrets-manager` guidance — re-run the two commands above,
don't hand-edit the Secret.

## Verification

1. `bash scripts/test-traffic-flow.sh` — confirms the new east-west NLBs
   didn't break the existing north-south path or introduce a `0.0.0.0/0` SG
   rule.
2. Confirm ztunnel/cni/istiod are healthy on both clusters:
   ```bash
   kubectl get pods -n istio-system --context mall-apne2-az-a
   kubectl get pods -n istio-system --context mall-apne2-az-c
   ```
3. Confirm cross-cluster endpoints resolved (should list pod IPs from both
   AZs for `payment`):
   ```bash
   istioctl proxy-config endpoints <api-gateway-pod> -n platform \
     --context mall-apne2-az-a | grep payment
   ```
4. **Failover test** — simulate az-a's payment dying and confirm az-a's
   api-gateway still serves payment requests (via az-c):
   ```bash
   kubectl scale deployment/payment -n core-services --replicas=0 \
     --context mall-apne2-az-a
   # then exercise the payment path through mall-kr.atomai.click and confirm
   # it still succeeds — check OTel/Grafana traces for a cross-AZ hop
   # (availability_zone=ap-northeast-2c on a request that entered via az-a)
   kubectl scale deployment/payment -n core-services --replicas=<original> \
     --context mall-apne2-az-a
   ```
5. Confirm steady-state (both AZs healthy) keeps traffic local — cross-AZ
   trace volume should be near zero, since ambient prefers local endpoints.

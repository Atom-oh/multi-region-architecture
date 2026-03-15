# ArgoCD GitOps Design - App-of-ApplicationSets

## Document Information

| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | 2026-03-15 |
| Status | In Progress |
| Classification | Internal |

---

## 1. Overview

### 1.1 GitOps Strategy

The platform uses ArgoCD with the **App-of-ApplicationSets** pattern for multi-cluster GitOps:

- **Single ArgoCD instance** in us-east-1 manages both regions
- **ApplicationSets** dynamically generate Applications per cluster
- **Kustomize overlays** provide region-specific configuration
- **Automated sync** with prune and self-heal for continuous reconciliation

### 1.2 Why App-of-ApplicationSets?

| Pattern | Pros | Cons |
|---------|------|------|
| App-of-Apps | Simple, manual control | Doesn't scale to multi-cluster |
| ApplicationSets only | DRY, multi-cluster native | No grouping hierarchy |
| **App-of-ApplicationSets** | **Hierarchical + DRY + multi-cluster** | Slightly more complex |

The App-of-ApplicationSets pattern combines:
1. A **root Application** that watches the `apps/` directory
2. **ApplicationSets** in that directory that generate per-cluster Applications
3. Each generated Application deploys a service group via Kustomize overlays

---

## 2. Architecture

### 2.1 Hierarchy

```
Root Application (root)
│
├── ApplicationSet: core-services
│   ├── App: core-services-us-east-1  → k8s/overlays/us-east-1 (core)
│   └── App: core-services-us-west-2  → k8s/overlays/us-west-2 (core)
│
├── ApplicationSet: user-services
│   ├── App: user-services-us-east-1  → k8s/overlays/us-east-1 (user)
│   └── App: user-services-us-west-2  → k8s/overlays/us-west-2 (user)
│
├── ApplicationSet: fulfillment
│   ├── App: fulfillment-us-east-1    → k8s/overlays/us-east-1 (fulfillment)
│   └── App: fulfillment-us-west-2    → k8s/overlays/us-west-2 (fulfillment)
│
├── ApplicationSet: business-services
│   ├── App: business-us-east-1       → k8s/overlays/us-east-1 (business)
│   └── App: business-us-west-2       → k8s/overlays/us-west-2 (business)
│
├── ApplicationSet: platform
│   ├── App: platform-us-east-1       → k8s/overlays/us-east-1 (platform)
│   └── App: platform-us-west-2       → k8s/overlays/us-west-2 (platform)
│
└── ApplicationSet: infra
    ├── App: infra-us-east-1          → k8s/infra (karpenter, etc.)
    └── App: infra-us-west-2          → k8s/infra (karpenter, etc.)
```

### 2.2 Cluster Registration

| Cluster | Type | Label |
|---------|------|-------|
| us-east-1 EKS | in-cluster | `region=us-east-1` |
| us-west-2 EKS | external | `region=us-west-2` |

The in-cluster server (`https://kubernetes.default.svc`) must also be labeled:
```bash
argocd cluster set https://kubernetes.default.svc \
  --label region=us-east-1
```

---

## 3. ApplicationSet Generator Design

### 3.1 Clusters Generator

Each ApplicationSet uses the `clusters` generator to dynamically discover clusters:

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          region: "{{region}}"
```

Available template variables:
- `{{name}}` - cluster name
- `{{server}}` - cluster API server URL
- `{{metadata.labels.region}}` - region label value

### 3.2 Sync Policy

All ApplicationSets use the same sync policy:

```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in Git
    selfHeal: true   # Revert manual changes
  syncOptions:
    - CreateNamespace=true
    - ApplyOutOfSyncOnly=true
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

### 3.3 Health Checks

ArgoCD monitors:
- Deployment rollout status
- Pod readiness
- Service endpoint availability
- ConfigMap/Secret sync status

---

## 4. Namespace Strategy

| ApplicationSet | Target Namespace | Created By |
|----------------|-----------------|------------|
| core-services | core-services | ArgoCD (CreateNamespace) |
| user-services | user-services | ArgoCD (CreateNamespace) |
| fulfillment | fulfillment | ArgoCD (CreateNamespace) |
| business-services | business-services | ArgoCD (CreateNamespace) |
| platform | platform | ArgoCD (CreateNamespace) |
| infra | karpenter, monitoring, logging | ArgoCD (CreateNamespace) |

---

## 5. Deployment Flow

### 5.1 Initial Deployment

```
Developer pushes to main
         │
         ▼
ArgoCD detects change (3-min poll or webhook)
         │
         ▼
Root App syncs → discovers ApplicationSet changes
         │
         ▼
ApplicationSets regenerate Applications
         │
         ▼
Each Application syncs Kustomize overlay
         │
    ┌────┴────┐
    ▼         ▼
us-east-1   us-west-2
(primary)   (secondary)
```

### 5.2 Progressive Rollout (Future)

For production safety, consider:
1. **Canary**: Argo Rollouts with traffic splitting
2. **Blue/Green**: Primary region first, then secondary
3. **Region-gated**: Manual sync for secondary region

---

## 6. Monitoring

### 6.1 ArgoCD Metrics

ArgoCD exposes Prometheus metrics:
- `argocd_app_sync_total` - sync attempts
- `argocd_app_health_status` - app health
- `argocd_app_reconcile_duration` - reconciliation time

### 6.2 Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| App OutOfSync | Sync status != Synced for > 10min | Warning |
| App Degraded | Health status == Degraded for > 5min | Critical |
| Sync Failed | Sync operation failed | Critical |
| Controller Down | argocd-application-controller not running | Critical |

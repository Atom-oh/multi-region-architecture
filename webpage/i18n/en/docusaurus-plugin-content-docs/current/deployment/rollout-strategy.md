---
sidebar_position: 5
title: Rollout Strategy
description: Rolling Update strategy, canary deployment, rollback procedures, regional deployment order
---

# Rollout Strategy

The multi-region shopping mall platform uses **Rolling Update** strategy as the default for safe deployments, and minimizes failure impact through **sequential deployment** between regions.

## Deployment Strategy Overview

```mermaid
flowchart TB
    subgraph "Deployment Order"
        direction LR
        W2["1. us-west-2<br/>(Secondary)"]
        VERIFY["2. Verification"]
        E1["3. us-east-1<br/>(Primary)"]
    end

    subgraph "Within Each Region"
        direction TB
        ROLL["Rolling Update"]
        POD1["Pod v1"]
        POD2["Pod v1 -> v2"]
        POD3["Pod v2"]
    end

    W2 -->|"Success"| VERIFY
    VERIFY -->|"Pass"| E1

    ROLL --> POD1
    POD1 --> POD2
    POD2 --> POD3
```

## Regional Deployment Order

### Secondary First Strategy

Deploy to the secondary region (us-west-2) first to detect issues early:

```mermaid
sequenceDiagram
    participant CI as CI/CD
    participant W2 as us-west-2
    participant HC as Health Check
    participant E1 as us-east-1

    CI->>W2: 1. Deploy to Secondary
    W2->>W2: Rolling Update
    W2-->>CI: Deployment Complete

    CI->>HC: 2. Verify Health
    HC->>W2: Check /health
    W2-->>HC: 200 OK

    CI->>HC: 3. Smoke Test
    HC->>W2: Run tests
    W2-->>HC: All passed

    Note over CI,E1: After Secondary verification complete

    CI->>E1: 4. Deploy to Primary
    E1->>E1: Rolling Update
    E1-->>CI: Deployment Complete

    CI->>HC: 5. Final Verification
    HC->>E1: Check /health
    E1-->>HC: 200 OK
```

### Rationale for Deployment Order

| Order | Region | Reason |
|-------|--------|--------|
| 1 | us-west-2 (Secondary) | Lower traffic, minimizes impact if issues occur |
| 2 | Verification | Health checks and smoke tests |
| 3 | us-east-1 (Primary) | Deploy to main traffic region after verification |

## Rolling Update Strategy

### Deployment Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  replicas: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%        # Maximum additional Pods
      maxUnavailable: 25%  # Maximum unavailable Pods
  template:
    spec:
      containers:
        - name: order-service
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3
```

### Rolling Update Process

```mermaid
flowchart LR
    subgraph "Initial State"
        P1_1["Pod v1"]
        P2_1["Pod v1"]
        P3_1["Pod v1"]
        P4_1["Pod v1"]
        P5_1["Pod v1"]
    end

    subgraph "Step 1 (maxSurge 25%)"
        P1_2["Pod v1"]
        P2_2["Pod v1"]
        P3_2["Pod v1"]
        P4_2["Pod v1"]
        P5_2["Pod v1"]
        P6_2["Pod v2 (NEW)"]
    end

    subgraph "Step 2 (maxUnavailable 25%)"
        P1_3["Pod v2"]
        P2_3["Pod v1"]
        P3_3["Pod v1"]
        P4_3["Pod v1"]
        P5_3["Pod v1"]
    end

    subgraph "Final State"
        P1_4["Pod v2"]
        P2_4["Pod v2"]
        P3_4["Pod v2"]
        P4_4["Pod v2"]
        P5_4["Pod v2"]
    end
```

## Canary Deployment (Consideration)

Currently using Rolling Update, but **Argo Rollouts** canary deployment can be considered for the future:

### Argo Rollouts Example

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: order-service
spec:
  replicas: 5
  strategy:
    canary:
      steps:
        - setWeight: 10
        - pause: { duration: 5m }
        - setWeight: 30
        - pause: { duration: 5m }
        - setWeight: 50
        - pause: { duration: 5m }
        - setWeight: 100
      trafficRouting:
        alb:
          ingress: order-service-ingress
          servicePort: 80
  selector:
    matchLabels:
      app: order-service
```

### Canary Deployment Flow

```mermaid
flowchart LR
    subgraph "Traffic Distribution"
        T10["10%"]
        T30["30%"]
        T50["50%"]
        T100["100%"]
    end

    subgraph "Verification"
        V1["Check Metrics"]
        V2["Error Rate Check"]
        V3["Latency Check"]
    end

    T10 --> V1
    V1 -->|"OK"| T30
    T30 --> V2
    V2 -->|"OK"| T50
    T50 --> V3
    V3 -->|"OK"| T100
```

## Rollback Procedures

### Automatic Rollback (ArgoCD)

ArgoCD automatically rolls back to the previous state on deployment failure:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

### Manual Rollback

#### Method 1: ArgoCD CLI

```bash
# Rollback to previous version
argocd app rollback order-service <revision>

# Sync to specific commit
argocd app sync order-service --revision <commit-hash>
```

#### Method 2: Git Revert

```bash
# Revert the problematic commit
git revert <commit-hash>
git push origin main

# ArgoCD automatically detects and syncs the change
```

#### Method 3: kubectl Direct Rollback

```bash
# Deployment rollback
kubectl rollout undo deployment/order-service -n core-services

# Rollback to specific revision
kubectl rollout undo deployment/order-service -n core-services --to-revision=2

# Check rollback status
kubectl rollout status deployment/order-service -n core-services
```

### Rollback Decision Criteria

| Metric | Threshold | Action |
|--------|-----------|--------|
| Error Rate | > 5% | Immediate rollback |
| P99 Latency | > 2 seconds | Review and rollback |
| Pod Restarts | > 3 times/5min | Immediate rollback |
| Health Check Failures | 3 consecutive | Automatic rollback |

## Deployment Verification

### Health Checks

```bash
# Check all Pod status
kubectl get pods -n core-services -l app=order-service

# Check Pod readiness
kubectl wait --for=condition=ready pod \
  -l app=order-service \
  -n core-services \
  --timeout=300s
```

### Smoke Tests

```bash
# API endpoint test
curl -f https://api.atomai.click/health

# Key functionality test
curl -X POST https://api.atomai.click/api/v1/orders/validate \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

### Metrics Verification

```promql
# Check error rate
sum(rate(http_requests_total{status=~"5.."}[5m])) /
sum(rate(http_requests_total[5m])) * 100

# P99 latency
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

## Emergency Deployment Procedures

### Hotfix Deployment

```mermaid
flowchart LR
    subgraph "Hotfix Flow"
        HF["hotfix/* branch"]
        PR["PR to main"]
        MERGE["Merge"]
        DEPLOY["Deploy to both regions"]
    end

    HF --> PR
    PR -->|"Emergency approval"| MERGE
    MERGE --> DEPLOY
```

### Emergency Deployment Checklist

1. [ ] Identify issue and create hotfix branch
2. [ ] Apply fix and test
3. [ ] Create PR and emergency review
4. [ ] Merge to main branch
5. [ ] Monitor deployment
6. [ ] Prepare rollback (if needed)

## Deployment Monitoring

### Real-time Monitoring

```bash
# Real-time deployment status
kubectl rollout status deployment/order-service -n core-services -w

# Check Pod events
kubectl get events -n core-services --sort-by='.lastTimestamp' | tail -20

# Check logs
kubectl logs -f deployment/order-service -n core-services
```

### Grafana Dashboards

- **Deployment Status**: Deployment progress
- **Error Rate**: Error rate trends
- **Latency**: Response time trends
- **Pod Status**: Pod status changes

## Next Steps

- [GitOps - ArgoCD](/deployment/gitops-argocd) - ArgoCD configuration
- [CI/CD Pipeline](/deployment/ci-cd-pipeline) - GitHub Actions
- [Observability](/observability/distributed-tracing) - Distributed tracing

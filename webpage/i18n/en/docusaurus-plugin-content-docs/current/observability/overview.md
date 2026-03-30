---
sidebar_position: 1
---

# Observability Overview

This section introduces the complete observability stack for the multi-region shopping mall platform. To quickly identify and resolve issues in distributed systems, we integrate three core elements: **Traces**, **Metrics**, and **Logs**.

## Three Pillars of Observability

```mermaid
graph TB
    subgraph "Three Pillars of Observability"
        T[Traces<br/>Distributed Tracing]
        M[Metrics<br/>Metrics]
        L[Logs<br/>Logs]
    end

    subgraph "Unified Analysis"
        G[Grafana<br/>Unified Dashboard]
    end

    T --> G
    M --> G
    L --> G

    G --> A[Alert Manager<br/>Alerting]
    G --> I[Incident Response<br/>Incident Response]
```

| Pillar | Purpose | Tools |
|--------|---------|-------|
| **Traces** | Track entire request flow | OpenTelemetry, Tempo, X-Ray |
| **Metrics** | Quantify system state | Prometheus, CloudWatch |
| **Logs** | Detailed event records | Fluent Bit, CloudWatch Logs |

## Overall Architecture

```mermaid
flowchart TB
    subgraph "Applications"
        GO[Go Services<br/>gin + otel-go]
        JAVA[Java Services<br/>Spring + Micrometer]
        PY[Python Services<br/>FastAPI + opentelemetry-python]
    end

    subgraph "Collection Layer"
        OTEL[OpenTelemetry Collector<br/>DaemonSet]
        FB[Fluent Bit<br/>DaemonSet]
    end

    subgraph "Storage & Analysis"
        subgraph "Traces"
            TEMPO[Grafana Tempo<br/>S3 Backend]
            XRAY[AWS X-Ray]
        end

        subgraph "Metrics"
            PROM[Prometheus<br/>15-day retention]
            CW[CloudWatch Metrics]
        end

        subgraph "Logs"
            CWL[CloudWatch Logs<br/>90-day retention]
        end
    end

    subgraph "Visualization"
        GRAF[Grafana<br/>Unified Dashboard]
        CWDB[CloudWatch Dashboard]
    end

    GO -->|OTLP gRPC| OTEL
    JAVA -->|OTLP gRPC| OTEL
    PY -->|OTLP gRPC| OTEL

    GO -->|stdout JSON| FB
    JAVA -->|stdout JSON| FB
    PY -->|stdout JSON| FB

    OTEL -->|traces| TEMPO
    OTEL -->|traces| XRAY
    OTEL -->|metrics| PROM

    FB -->|logs| CWL

    TEMPO --> GRAF
    PROM --> GRAF
    CWL --> GRAF

    CW --> CWDB
    CWL --> CWDB
```

## Core Components

### 1. OpenTelemetry Collector (DaemonSet)

Runs on all nodes and collects telemetry data from application Pods.

```yaml
# Receiver Ports
- OTLP gRPC: 4317
- OTLP HTTP: 4318
- Prometheus metrics: 8889

# Key Features
- Tail-based Sampling (errors 100%, slow requests 100%, default 10%)
- Batch processing (1024 batch size)
- Memory limit (512Mi)
```

**Dual Export:**
- **Grafana Tempo**: Long-term storage and detailed analysis
- **AWS X-Ray**: AWS service integration and service map

### 2. Prometheus + Grafana

```yaml
# Prometheus Settings
retention: 15d
storage: 50Gi (gp3)
serviceMonitor: Auto-discovery

# Grafana Settings
persistence: 10Gi
dataSource:
  - Prometheus (default)
  - Tempo (traces)
  - CloudWatch (AWS metrics)
```

### 3. Fluent Bit (DaemonSet)

Collects all container logs and sends them to CloudWatch Logs.

```yaml
# Log Group Structure
/eks/{cluster-name}/containers

# Log Stream
{node-name}-{container-name}

# Retention Period
90 days
```

### 4. CloudWatch Integration

CloudWatch resources managed by Terraform:

```hcl
# Log Groups by Namespace
- /eks/multi-region-mall/core-services
- /eks/multi-region-mall/user-services
- /eks/multi-region-mall/fulfillment
- /eks/multi-region-mall/business-services
- /eks/multi-region-mall/platform

# Key Alarms
- high-error-rate: 5XX error rate > 1%
- high-latency: Response time > 2 seconds
- aurora-replication-lag: Replication lag > 1000ms
- msk-under-replicated: Under-replicated partition detected
```

## Detailed Data Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant OTel as OTel Collector
    participant Tempo as Grafana Tempo
    participant XRay as AWS X-Ray
    participant Prom as Prometheus
    participant FB as Fluent Bit
    participant CWL as CloudWatch Logs
    participant Graf as Grafana

    App->>OTel: OTLP (traces + metrics)
    App->>FB: stdout (logs)

    OTel->>OTel: Tail Sampling
    OTel->>Tempo: traces (gRPC)
    OTel->>XRay: traces (AWS API)
    OTel->>Prom: metrics (scrape)

    FB->>FB: Add Kubernetes metadata
    FB->>CWL: logs (JSON)

    Graf->>Tempo: Query traces
    Graf->>Prom: Query metrics
    Graf->>CWL: Query logs

    Note over Graf: Connect logs and traces via trace_id
```

## Regional Configuration

Each region (us-east-1, us-west-2) operates an independent observability stack:

| Component | us-east-1 | us-west-2 |
|-----------|-----------|-----------|
| OTel Collector | DaemonSet | DaemonSet |
| Tempo | S3 bucket (use1) | S3 bucket (usw2) |
| Prometheus | 50Gi PVC | 50Gi PVC |
| CloudWatch | /eks/multi-region-mall/* | /eks/multi-region-mall/* |

### Tempo IRSA Configuration

Regional IAM Roles are automatically patched through ArgoCD ApplicationSet:

```yaml
# appset-tempo.yaml
patches:
  - target:
      kind: ServiceAccount
      name: tempo
    patch: |-
      - op: replace
        path: /metadata/annotations/eks.amazonaws.com~1role-arn
        value: "arn:aws:iam::123456789012:role/production-tempo-{{metadata.labels.region}}"
```

## Alerting and Escalation

```mermaid
flowchart LR
    subgraph "Detection"
        PA[Prometheus Alerts]
        CWA[CloudWatch Alarms]
    end

    subgraph "Notification"
        AM[AlertManager]
        SNS[SNS Topic]
    end

    subgraph "Channels"
        SL[Slack]
        PD[PagerDuty]
        EM[Email]
    end

    PA --> AM
    CWA --> SNS

    AM --> SL
    AM --> PD
    SNS --> EM
    SNS --> SL
```

## Quick Start

### 1. Access Grafana

```bash
# Port forwarding
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Access in browser
open http://localhost:3000
# Default account: admin / prom-operator
```

### 2. Search Traces

```bash
# Search traces via Tempo API
curl -G http://localhost:3200/api/search \
  --data-urlencode 'tags=service.name=order-service' \
  --data-urlencode 'minDuration=500ms'
```

### 3. Query Logs

```bash
# CloudWatch Logs Insights
aws logs start-query \
  --log-group-name "/eks/multi-region-mall/core-services" \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | limit 100'
```

## Related Documentation

- [Distributed Tracing](/observability/distributed-tracing) - OpenTelemetry detailed configuration
- [Prometheus Metrics](/observability/metrics-prometheus) - Metrics collection and alerting
- [Logging](/observability/logging) - Fluent Bit and log format
- [Dashboards](/observability/dashboards) - Grafana dashboard configuration

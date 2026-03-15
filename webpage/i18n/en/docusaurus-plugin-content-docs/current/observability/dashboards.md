---
sidebar_position: 5
---

# Grafana Dashboards

Grafana is used to visualize and monitor system status. We provide service overview, infrastructure, business metrics, and multi-region comparison dashboards.

## Dashboard Configuration

```mermaid
flowchart TB
    subgraph "Data Sources"
        PROM[Prometheus<br/>Metrics]
        TEMPO[Tempo<br/>Traces]
        CWL[CloudWatch<br/>Logs/AWS Metrics]
    end

    subgraph "Dashboards"
        SVC[Service Overview<br/>RED Metrics]
        INFRA[Infrastructure<br/>Nodes/DB/Cache]
        BIZ[Business<br/>Orders/Payments/Revenue]
        MULTI[Multi-Region<br/>Region Comparison]
    end

    PROM --> SVC
    PROM --> INFRA
    PROM --> BIZ
    PROM --> MULTI

    TEMPO --> SVC
    CWL --> INFRA
    CWL --> MULTI
```

## 1. Service Overview Dashboard (RED Metrics)

View key metrics for each microservice at a glance.

### Layout

```
+----------------------------------+----------------------------------+
|        Request Rate (QPS)         |         Error Rate (%)           |
|    [Line Chart - by service]      |    [Line Chart - by service]     |
+----------------------------------+----------------------------------+
|              P50 Latency          |              P99 Latency          |
|    [Line Chart - by service]      |    [Line Chart - by service]     |
+----------------------------------+----------------------------------+
|                    Service Map (Tempo)                               |
|                    [Node Graph - service relationships]              |
+---------------------------------------------------------------------+
|                    Active Traces                                     |
|                    [Table - recent error/slow traces]                |
+---------------------------------------------------------------------+
```

### Panel Queries

**Request Rate (QPS)**
```promql
sum(rate(http_requests_total[5m])) by (service)
```

**Error Rate (%)**
```promql
(
  sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
  /
  sum(rate(http_requests_total[5m])) by (service)
) * 100
```

**P50 Latency**
```promql
histogram_quantile(0.50,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)
```

**P99 Latency**
```promql
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)
```

### Service Status Table

```promql
# Up/Down status
up{job=~".*service.*"}

# Pod count
count(kube_pod_status_ready{condition="true"}) by (deployment)
```

## 2. Infrastructure Dashboard

Monitor infrastructure components such as EKS nodes, databases, and cache.

### Layout

```
+------------------+------------------+------------------+
|   Node CPU (%)   |  Node Memory (%) |   Node Count     |
|   [Gauge Panel]  |   [Gauge Panel]  |   [Stat Panel]   |
+------------------+------------------+------------------+
|                Node Resource Usage by Instance                |
|                [Time Series - CPU/Memory/Disk]               |
+-------------------------------------------------------------+
|   Aurora Connections  |  Aurora Replica Lag  |  Aurora IOPS  |
|    [Time Series]      |    [Time Series]     |  [Time Series]|
+-------------------------------------------------------------+
|  ElastiCache Memory   | ElastiCache Hits/Miss| ElastiCache Conn|
|    [Time Series]      |    [Time Series]     |  [Time Series]|
+-------------------------------------------------------------+
|    MSK Bytes In/Out   |  MSK Consumer Lag    | MSK Partitions |
|    [Time Series]      |    [Time Series]     |   [Stat Panel] |
+-------------------------------------------------------------+
```

### Panel Queries

**Node CPU Usage**
```promql
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)) * 100
```

**Node Memory Usage**
```promql
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
```

**Aurora Connections**
```promql
# CloudWatch metrics
aws_rds_database_connections_average{dbinstance_identifier=~"production-aurora.*"}
```

**Aurora Replication Lag**
```promql
aws_rds_aurora_replica_lag_average{dbinstance_identifier=~"production-aurora.*"}
```

**ElastiCache Memory Usage**
```promql
aws_elasticache_database_memory_usage_percentage_average{cache_cluster_id=~"production-elasticache.*"}
```

**MSK Consumer Lag**
```promql
aws_kafka_sum_offset_lag_sum{consumer_group=~".*"}
```

## 3. Business Dashboard

Track business metrics such as orders, payments, and revenue.

### Layout

```
+------------------+------------------+------------------+
|  Orders/min      |  Payment Success |   Revenue Today  |
|   [Stat Panel]   |   [Gauge Panel]  |   [Stat Panel]   |
+------------------+------------------+------------------+
|                    Orders Over Time                      |
|          [Time Series - by order status]                 |
+----------------------------------------------------------+
|        Payment Methods         |    Payment Status       |
|        [Pie Chart]             |    [Bar Chart]          |
+----------------------------------------------------------+
|                    Top Selling Products                   |
|                    [Table - popular products]             |
+----------------------------------------------------------+
|    Active Carts    |   Wishlist Items  |  Review Count   |
|   [Stat Panel]     |   [Stat Panel]    |  [Stat Panel]   |
+----------------------------------------------------------+
```

### Panel Queries

**Orders per Minute**
```promql
sum(rate(orders_total[1m])) * 60
```

**Payment Success Rate**
```promql
(
  sum(rate(payments_total{status="success"}[5m]))
  /
  sum(rate(payments_total[5m]))
) * 100
```

**Orders by Status Over Time**
```promql
sum(increase(orders_total[5m])) by (status)
```

**Payment Method Distribution**
```promql
sum(payments_total) by (method)
```

**Popular Products (Top 10)**
```promql
topk(10, sum(order_items_total) by (product_id, product_name))
```

## 4. Multi-Region Comparison Dashboard

Compare status between us-east-1 and us-west-2 regions.

### Layout

```
+---------------------------+---------------------------+
|        us-east-1          |        us-west-2          |
|  [Region Status Badge]    |  [Region Status Badge]    |
+---------------------------+---------------------------+
|    Request Rate           |    Request Rate           |
|    [Time Series]          |    [Time Series]          |
+---------------------------+---------------------------+
|    Error Rate             |    Error Rate             |
|    [Time Series]          |    [Time Series]          |
+---------------------------+---------------------------+
|                  Cross-Region Latency                  |
|                  [Time Series - inter-region delay]    |
+--------------------------------------------------------+
|      Aurora Replication Lag      |   Route53 Health    |
|        [Time Series]             |    [Status Panel]   |
+--------------------------------------------------------+
|                 Traffic Distribution                   |
|                 [Pie Chart - traffic by region]        |
+--------------------------------------------------------+
```

### Panel Queries

**Request Rate by Region**
```promql
sum(rate(http_requests_total[5m])) by (region)
```

**Error Rate by Region**
```promql
(
  sum(rate(http_requests_total{status=~"5.."}[5m])) by (region)
  /
  sum(rate(http_requests_total[5m])) by (region)
) * 100
```

**Aurora Replication Lag (Cross-Region)**
```promql
aws_rds_aurora_replica_lag_average{dbinstance_identifier=~".*us-west-2.*"}
```

**Traffic Distribution**
```promql
sum(increase(http_requests_total[1h])) by (region)
```

## Grafana Configuration

### Data Source Configuration

```yaml
# grafana-datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-kube-prometheus-prometheus.monitoring:9090
    isDefault: true

  - name: Tempo
    type: tempo
    url: http://tempo.observability:3200
    jsonData:
      tracesToLogsV2:
        datasourceUid: cloudwatch
        filterByTraceID: true
      tracesToMetrics:
        datasourceUid: prometheus
      serviceMap:
        datasourceUid: prometheus
      nodeGraph:
        enabled: true

  - name: CloudWatch
    type: cloudwatch
    jsonData:
      authType: default
      defaultRegion: us-east-1
```

### Dashboard Provisioning

```yaml
# grafana-dashboards.yaml
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards/default
```

## Alert Configuration

### Slack Alert Channel

```yaml
# alertmanager-config.yaml
receivers:
  - name: slack-notifications
    slack_configs:
      - api_url: ${SLACK_WEBHOOK_URL}
        channel: '#alerts-production'
        title: '{{ .Status | toUpper }}: {{ .CommonAnnotations.summary }}'
        text: '{{ .CommonAnnotations.description }}'
        send_resolved: true
```

### Alert Policy

```yaml
route:
  group_by: ['alertname', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: slack-notifications
  routes:
    - match:
        severity: critical
      receiver: pagerduty-critical
    - match:
        severity: warning
      receiver: slack-notifications
```

## Dashboard JSON Example

### Service Overview Panel

```json
{
  "panels": [
    {
      "title": "Request Rate (QPS)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
      "targets": [
        {
          "expr": "sum(rate(http_requests_total[5m])) by (service)",
          "legendFormat": "{{ service }}"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "reqps",
          "color": { "mode": "palette-classic" }
        }
      }
    },
    {
      "title": "Error Rate (%)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
      "targets": [
        {
          "expr": "(sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service)) * 100",
          "legendFormat": "{{ service }}"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "thresholds": {
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 1 },
              { "color": "red", "value": 5 }
            ]
          }
        }
      }
    }
  ]
}
```

## CloudWatch Dashboard

AWS CloudWatch dashboard managed by Terraform:

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "production-platform-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title = "ALB Request Count"
          metrics = [["AWS/ApplicationELB", "RequestCount"]]
        }
      },
      {
        type = "metric"
        properties = {
          title = "ALB Response Time"
          metrics = [["AWS/ApplicationELB", "TargetResponseTime"]]
        }
      },
      {
        type = "metric"
        properties = {
          title = "Aurora Replication Lag"
          metrics = [["AWS/RDS", "AuroraReplicaLag"]]
        }
      },
      {
        type = "metric"
        properties = {
          title = "MSK Bytes In/Out"
          metrics = [
            ["AWS/Kafka", "BytesInPerSec"],
            ["AWS/Kafka", "BytesOutPerSec"]
          ]
        }
      }
    ]
  })
}
```

## Access Instructions

```bash
# Grafana port forwarding
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Access in browser
open http://localhost:3000

# Default credentials
# Username: admin
# Password: prom-operator
```

## Related Documentation

- [Observability Overview](/observability/overview)
- [Prometheus Metrics](/observability/metrics-prometheus)
- [Distributed Tracing](/observability/distributed-tracing)

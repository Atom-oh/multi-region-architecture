---
sidebar_position: 4
---

# Logging

Fluent Bit DaemonSet is used to collect all container logs and send them to CloudWatch Logs. Structured JSON log format and trace ID integration enable efficient log analysis.

## Architecture

```mermaid
flowchart TB
    subgraph "EKS Node"
        subgraph "Application Pods"
            APP1[order-service<br/>JSON stdout]
            APP2[payment-service<br/>JSON stdout]
            APP3[inventory-service<br/>JSON stdout]
        end

        LOG[/var/log/containers/*.log]
        FB[Fluent Bit<br/>DaemonSet]
    end

    subgraph "AWS"
        CWL[CloudWatch Logs<br/>90-day retention]
        CWI[CloudWatch Logs Insights]
    end

    subgraph "Visualization"
        GRAF[Grafana<br/>CloudWatch Plugin]
    end

    APP1 -->|stdout| LOG
    APP2 -->|stdout| LOG
    APP3 -->|stdout| LOG

    LOG --> FB
    FB -->|AWS API| CWL
    CWL --> CWI
    CWL --> GRAF
```

## Fluent Bit Configuration

### DaemonSet Deployment

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: amazon-cloudwatch
spec:
  template:
    spec:
      serviceAccountName: fluent-bit  # IRSA
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule
        - key: node-pool
          operator: Exists
          effect: NoSchedule
      containers:
        - name: fluent-bit
          image: public.ecr.aws/aws-observability/aws-for-fluent-bit:stable
          env:
            - name: AWS_REGION
              valueFrom:
                configMapKeyRef:
                  name: cluster-info
                  key: region
            - name: CLUSTER_NAME
              valueFrom:
                configMapKeyRef:
                  name: cluster-info
                  key: cluster-name
            - name: HOST_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
              readOnly: true
```

### Fluent Bit Configuration

```ini
[SERVICE]
    Flush         5
    Log_Level     info
    Daemon        off
    Parsers_File  parsers.conf
    HTTP_Server   On
    HTTP_Listen   0.0.0.0
    HTTP_Port     2020

[INPUT]
    Name              tail
    Tag               kube.*
    Path              /var/log/containers/*.log
    Parser            docker
    DB                /var/log/flb_kube.db
    Mem_Buf_Limit     50MB
    Skip_Long_Lines   On
    Refresh_Interval  10

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
    Merge_Log           On
    Merge_Log_Key       log_processed
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off
    Labels              On
    Annotations         Off

[FILTER]
    Name    modify
    Match   kube.*
    Add     cluster ${CLUSTER_NAME}
    Add     region ${AWS_REGION}

[OUTPUT]
    Name                cloudwatch_logs
    Match               kube.*
    region              ${AWS_REGION}
    log_group_name      /eks/${CLUSTER_NAME}/containers
    log_stream_prefix   ${HOST_NAME}-
    auto_create_group   true
    log_format          json/emf
    retry_limit         2
```

## Standard Log Format

All services should output logs in the following JSON format:

```json
{
  "timestamp": "2026-03-15T10:30:45.123Z",
  "level": "INFO",
  "service": "order-service",
  "region": "us-east-1",
  "trace_id": "0af7651916cd43dd8448eb211c80319c",
  "span_id": "b7ad6b7169203331",
  "message": "Order created successfully",
  "order_id": "ORD-123456",
  "user_id": "a0000001-0000-0000-0000-000000000001",
  "amount": 159000,
  "duration_ms": 45
}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string (ISO 8601) | Log occurrence time |
| `level` | string | DEBUG, INFO, WARN, ERROR, FATAL |
| `service` | string | Service name |
| `region` | string | AWS region |
| `message` | string | Log message |

### Recommended Fields

| Field | Type | Description |
|-------|------|-------------|
| `trace_id` | string | OpenTelemetry trace ID |
| `span_id` | string | OpenTelemetry span ID |
| `user_id` | string | User ID |
| `request_id` | string | Request ID |
| `duration_ms` | number | Processing time (milliseconds) |

## Language-specific Logging Implementation

### Go (zerolog)

```go
import (
    "github.com/rs/zerolog"
    "github.com/rs/zerolog/log"
    "go.opentelemetry.io/otel/trace"
)

func init() {
    zerolog.TimeFieldFormat = time.RFC3339Nano

    log.Logger = zerolog.New(os.Stdout).With().
        Str("service", "order-service").
        Str("region", os.Getenv("AWS_REGION")).
        Timestamp().
        Logger()
}

// Logging with trace context
func LogWithTrace(ctx context.Context) zerolog.Logger {
    span := trace.SpanFromContext(ctx)
    if span.SpanContext().IsValid() {
        return log.With().
            Str("trace_id", span.SpanContext().TraceID().String()).
            Str("span_id", span.SpanContext().SpanID().String()).
            Logger()
    }
    return log.Logger
}

// Usage example
func CreateOrder(ctx context.Context, order *Order) error {
    logger := LogWithTrace(ctx)

    logger.Info().
        Str("order_id", order.ID).
        Str("user_id", order.UserID).
        Int64("amount", order.Amount).
        Msg("Order creation started")

    // Processing logic...

    logger.Info().
        Str("order_id", order.ID).
        Int64("duration_ms", elapsed.Milliseconds()).
        Msg("Order created successfully")

    return nil
}
```

### Java (Logback + Logstash Encoder)

```xml
<!-- logback-spring.xml -->
<configuration>
    <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <customFields>
                {"service":"payment-service","region":"${AWS_REGION:-unknown}"}
            </customFields>
            <provider class="net.logstash.logback.composite.loggingevent.LoggingEventPatternJsonProvider">
                <pattern>
                    {
                        "trace_id": "%mdc{traceId}",
                        "span_id": "%mdc{spanId}"
                    }
                </pattern>
            </provider>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="STDOUT"/>
    </root>
</configuration>
```

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;

@Service
public class PaymentService {
    private static final Logger log = LoggerFactory.getLogger(PaymentService.class);

    public PaymentResult processPayment(PaymentRequest request) {
        // Set additional context in MDC
        MDC.put("order_id", request.getOrderId());
        MDC.put("user_id", request.getUserId());

        try {
            log.info("Payment processing started - Amount: {}", request.getAmount());

            // Payment logic...

            log.info("Payment processing completed - Transaction: {}", result.getTransactionId());
            return result;

        } catch (Exception e) {
            log.error("Payment processing failed: {}", e.getMessage(), e);
            throw e;
        } finally {
            MDC.clear();
        }
    }
}
```

### Python (structlog)

```python
import structlog
import os
from opentelemetry import trace

def configure_logging():
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            structlog.processors.JSONRenderer()
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

def get_logger(name: str):
    logger = structlog.get_logger(name)
    return logger.bind(
        service="recommendation-service",
        region=os.getenv("AWS_REGION", "unknown")
    )

# Add trace context
def log_with_trace(logger, **kwargs):
    span = trace.get_current_span()
    if span.get_span_context().is_valid:
        kwargs["trace_id"] = format(span.get_span_context().trace_id, "032x")
        kwargs["span_id"] = format(span.get_span_context().span_id, "016x")
    return logger.bind(**kwargs)

# Usage example
logger = get_logger(__name__)

async def get_recommendations(user_id: str):
    ctx_logger = log_with_trace(logger, user_id=user_id)

    ctx_logger.info("Recommendation generation started")

    # Recommendation logic...

    ctx_logger.info(
        "Recommendation generation completed",
        item_count=len(recommendations),
        duration_ms=elapsed_ms
    )

    return recommendations
```

## Log Level Guidelines

| Level | Purpose | Examples |
|-------|---------|----------|
| **DEBUG** | Detailed info for development/debugging | Variable values, SQL queries |
| **INFO** | Normal operation records | Request start/complete, state changes |
| **WARN** | Potential issues | Retries, fallback usage |
| **ERROR** | Errors occurred (recoverable) | API call failures, validation failures |
| **FATAL** | Severe errors (unrecoverable) | Service startup failure |

## CloudWatch Logs Structure

### Log Groups

Log groups managed by Terraform:

```hcl
# Log groups by namespace
/eks/multi-region-mall/core-services
/eks/multi-region-mall/user-services
/eks/multi-region-mall/fulfillment
/eks/multi-region-mall/business-services
/eks/multi-region-mall/platform

# Retention period: 90 days
```

### Log Streams

```
{node-name}-{namespace}_{pod-name}_{container-name}-{container-id}
```

Example:
```
ip-10-0-1-123-core-services_order-service-abc123_order-service-def456
```

## CloudWatch Logs Insights Queries

### Search Error Logs

```sql
fields @timestamp, @message, service, trace_id, error
| filter level = "ERROR"
| sort @timestamp desc
| limit 100
```

### Track Specific Order

```sql
fields @timestamp, @message, service, level
| filter order_id = "ORD-123456"
| sort @timestamp asc
```

### Slow Request Analysis

```sql
fields @timestamp, service, message, duration_ms
| filter duration_ms > 1000
| stats avg(duration_ms) as avg_duration,
        max(duration_ms) as max_duration,
        count(*) as request_count
  by service
| sort avg_duration desc
```

### Connect Logs by Trace ID

```sql
fields @timestamp, @message, service, level, span_id
| filter trace_id = "0af7651916cd43dd8448eb211c80319c"
| sort @timestamp asc
```

### Error Rate by Service

```sql
fields service, level
| stats count(*) as total,
        sum(case when level = "ERROR" then 1 else 0 end) as errors
  by service
| display service, errors, total, (errors * 100.0 / total) as error_rate
| sort error_rate desc
```

### User Activity

```sql
fields @timestamp, service, message, user_id
| filter user_id = "a0000001-0000-0000-0000-000000000001"
| sort @timestamp desc
| limit 50
```

## Connecting Logs and Traces

Logs and traces can be queried together in Grafana:

```mermaid
sequenceDiagram
    participant User as User
    participant Graf as Grafana
    participant CWL as CloudWatch Logs
    participant Tempo as Grafana Tempo

    User->>Graf: Query error logs
    Graf->>CWL: Log query
    CWL-->>Graf: Logs (with trace_id)

    User->>Graf: Click trace_id
    Graf->>Tempo: TraceQL query
    Tempo-->>Graf: Complete trace

    Note over Graf: Integrated view of logs and traces
```

### Grafana Data Source Connection Configuration

```yaml
# Tempo data source
jsonData:
  tracesToLogsV2:
    datasourceUid: cloudwatch
    filterByTraceID: true
    filterBySpanID: true
    customQuery: true
    query: |
      fields @timestamp, @message, service, level
      | filter trace_id = "${__trace.traceId}"
      | sort @timestamp asc
```

## Sensitive Data Masking

Mask sensitive information to prevent it from appearing in logs:

### Go

```go
func maskSensitiveData(data string) string {
    // Mask credit card numbers
    cardRegex := regexp.MustCompile(`\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}`)
    data = cardRegex.ReplaceAllString(data, "****-****-****-****")

    // Mask email addresses
    emailRegex := regexp.MustCompile(`[\w.-]+@[\w.-]+\.\w+`)
    data = emailRegex.ReplaceAllStringFunc(data, func(email string) string {
        parts := strings.Split(email, "@")
        return parts[0][:2] + "***@" + parts[1]
    })

    return data
}
```

### Python

```python
import re

class SensitiveDataFilter:
    PATTERNS = [
        (re.compile(r'\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}'), '****-****-****-****'),
        (re.compile(r'[\w.-]+@[\w.-]+\.\w+'), lambda m: m.group()[:2] + '***@***'),
        (re.compile(r'password["\s:=]+["\']?\w+["\']?', re.I), 'password=***'),
    ]

    @classmethod
    def filter(cls, message: str) -> str:
        for pattern, replacement in cls.PATTERNS:
            if callable(replacement):
                message = pattern.sub(replacement, message)
            else:
                message = pattern.sub(replacement, message)
        return message
```

## Troubleshooting

### When Logs Are Not Collected

```bash
# 1. Check Fluent Bit status
kubectl get pods -n amazon-cloudwatch -l app=fluent-bit

# 2. Check Fluent Bit logs
kubectl logs -n amazon-cloudwatch -l app=fluent-bit --tail=100

# 3. Check CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix "/eks/multi-region-mall"

# 4. Check container logs directly
kubectl logs <pod-name> -n <namespace> --tail=50
```

### Log Format Validation

```bash
# Verify Pod logs are in JSON format
kubectl logs <pod-name> | head -5 | jq .

# Verify required fields
kubectl logs <pod-name> | head -1 | jq 'has("timestamp", "level", "service", "message")'
```

## Related Documentation

- [Observability Overview](/observability/overview)
- [Distributed Tracing](/observability/distributed-tracing)
- [Dashboards](/observability/dashboards)

---
sidebar_position: 2
---

# 분산 추적 (Distributed Tracing)

마이크로서비스 환경에서 요청의 전체 흐름을 추적하기 위한 분산 추적 시스템을 구성합니다. OpenTelemetry Collector를 중심으로 Grafana Tempo와 AWS X-Ray로 이중 내보내기(Dual Export)합니다.

## 아키텍처 개요

```mermaid
flowchart TB
    subgraph "Application Layer"
        GO[Go Services<br/>otel-go SDK]
        JAVA[Java Services<br/>OpenTelemetry Java Agent]
        PY[Python Services<br/>opentelemetry-python]
    end

    subgraph "Collection"
        OTEL[OpenTelemetry Collector<br/>DaemonSet]
    end

    subgraph "Processing"
        TS[Tail Sampling<br/>에러 100% / 느린요청 100% / 기본 10%]
        BATCH[Batch Processor<br/>1024개 단위]
    end

    subgraph "Export"
        TEMPO[Grafana Tempo<br/>S3 Backend]
        XRAY[AWS X-Ray]
    end

    subgraph "Visualization"
        GRAF[Grafana<br/>Tempo Datasource]
        XCON[X-Ray Console<br/>Service Map]
    end

    GO -->|OTLP gRPC :4317| OTEL
    JAVA -->|OTLP gRPC :4317| OTEL
    PY -->|OTLP gRPC :4317| OTEL

    OTEL --> TS
    TS --> BATCH
    BATCH --> TEMPO
    BATCH --> XRAY

    TEMPO --> GRAF
    XRAY --> XCON
```

## OpenTelemetry Collector 구성

### DaemonSet 배포

모든 노드에 OTel Collector가 배포되어 해당 노드의 Pod들로부터 텔레메트리를 수집합니다.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector
  namespace: platform
spec:
  template:
    spec:
      containers:
        - name: otel-collector
          image: public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0
          ports:
            - name: otlp-grpc
              containerPort: 4317
              hostPort: 4317      # 노드 포트로 노출
            - name: otlp-http
              containerPort: 4318
              hostPort: 4318
            - name: metrics
              containerPort: 8889  # Prometheus scrape용
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1Gi
```

### Collector 설정

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  # 메모리 제한
  memory_limiter:
    check_interval: 5s
    limit_mib: 512
    spike_limit_mib: 128

  # Tail-based Sampling
  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    expected_new_traces_per_sec: 1000
    policies:
      - name: errors-policy        # 에러는 100% 수집
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow-requests-policy # 500ms 이상 100% 수집
        type: latency
        latency:
          threshold_ms: 500
      - name: probabilistic-policy # 나머지는 10% 샘플링
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

  # 배치 처리
  batch:
    timeout: 5s
    send_batch_size: 1024
    send_batch_max_size: 2048

  # 리소스 속성 추가
  resource:
    attributes:
      - key: k8s.cluster.name
        value: mall-cluster
        action: upsert

exporters:
  # Tempo로 내보내기
  otlp/tempo:
    endpoint: tempo.observability.svc.cluster.local:4317
    tls:
      insecure: true

  # X-Ray로 내보내기
  awsxray:
    region: ${AWS_REGION}
    index_all_attributes: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling, batch, resource]
      exporters: [otlp/tempo, awsxray]
```

## Tail-based Sampling 전략

```mermaid
flowchart TD
    T[Trace 수신] --> D{Decision Wait<br/>10초}
    D --> E{에러 포함?}
    E -->|Yes| C1[100% 수집]
    E -->|No| L{Latency > 500ms?}
    L -->|Yes| C2[100% 수집]
    L -->|No| P{확률 샘플링}
    P -->|10%| C3[수집]
    P -->|90%| DR[폐기]

    C1 --> EX[Export to Tempo + X-Ray]
    C2 --> EX
    C3 --> EX
```

| 정책 | 조건 | 샘플링 비율 | 목적 |
|------|------|-------------|------|
| **errors-policy** | status_code = ERROR | 100% | 모든 에러 트레이스 보존 |
| **slow-requests-policy** | latency > 500ms | 100% | 성능 문제 분석 |
| **probabilistic-policy** | 기타 | 10% | 비용 최적화 |

## Grafana Tempo 설정

### Monolithic Mode 배포

단일 인스턴스로 모든 컴포넌트(distributor, ingester, compactor, querier)를 실행합니다.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: observability
spec:
  replicas: 1
  template:
    spec:
      serviceAccountName: tempo  # IRSA 사용
      containers:
        - name: tempo
          image: grafana/tempo:2.6.1
          args:
            - -config.file=/etc/tempo/tempo.yaml
            - -config.expand-env=true
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: "1"
              memory: 2Gi
```

### Tempo 설정 (S3 Backend)

```yaml
server:
  http_listen_port: 3200
  grpc_listen_port: 9095

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 720h    # 30일 보관

# 메트릭 생성기 (서비스 그래프, 스팬 메트릭)
metrics_generator:
  registry:
    external_labels:
      source: tempo
      cluster: mall-cluster
  storage:
    path: /var/tempo/generator/wal
    remote_write:
      - url: http://prometheus-kube-prometheus-prometheus.monitoring:9090/api/v1/write
        send_exemplars: true

# S3 스토리지
storage:
  trace:
    backend: s3
    s3:
      bucket: ${TEMPO_S3_BUCKET}
      region: ${AWS_REGION}
    wal:
      path: /var/tempo/wal
    local:
      path: /var/tempo/blocks
```

### ArgoCD ApplicationSet (리전별 IRSA)

Tempo는 전용 ApplicationSet으로 관리되어 리전별로 다른 IAM Role을 패치합니다.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tempo
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchExpressions:
            - key: region
              operator: Exists
  template:
    metadata:
      name: 'infra-tempo-{{metadata.labels.region}}'
    spec:
      source:
        repoURL: https://github.com/Atom-oh/multi-region-architecture.git
        path: k8s/infra/tempo
        kustomize:
          patches:
            - target:
                kind: ServiceAccount
                name: tempo
              patch: |-
                - op: replace
                  path: /metadata/annotations/eks.amazonaws.com~1role-arn
                  value: "arn:aws:iam::180294183052:role/production-tempo-{{metadata.labels.region}}"
```

## SDK 계측 (Instrumentation)

### Go 서비스

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
)

func initTracer() (*trace.TracerProvider, error) {
    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint("otel-collector.platform:4317"),
        otlptracegrpc.WithInsecure(),
    )
    if err != nil {
        return nil, err
    }

    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),
        trace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceName("order-service"),
            semconv.ServiceVersion("1.0.0"),
            attribute.String("region", os.Getenv("AWS_REGION")),
        )),
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}

// Gin 미들웨어 적용
router := gin.New()
router.Use(otelgin.Middleware("order-service"))
```

### Java 서비스 (Spring Boot)

```yaml
# application.yaml
management:
  tracing:
    sampling:
      probability: 1.0
  otlp:
    tracing:
      endpoint: http://otel-collector.platform:4317

spring:
  application:
    name: payment-service
```

```xml
<!-- pom.xml -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

### Python 서비스 (FastAPI)

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

def init_tracer():
    provider = TracerProvider(
        resource=Resource.create({
            "service.name": "recommendation-service",
            "service.version": "1.0.0",
            "deployment.environment": os.getenv("ENV", "production"),
        })
    )

    exporter = OTLPSpanExporter(
        endpoint="otel-collector.platform:4317",
        insecure=True
    )
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

# FastAPI 자동 계측
app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
```

## Kafka 메시지 트레이스 전파

Kafka를 통한 비동기 메시지에서도 트레이스 컨텍스트를 전파합니다.

### Producer (Go)

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
)

func produceMessage(ctx context.Context, topic string, value []byte) error {
    // 트레이스 컨텍스트를 헤더에 주입
    headers := make([]kafka.Header, 0)
    carrier := propagation.MapCarrier{}
    otel.GetTextMapPropagator().Inject(ctx, carrier)

    for k, v := range carrier {
        headers = append(headers, kafka.Header{
            Key:   k,
            Value: []byte(v),
        })
    }

    return producer.Produce(&kafka.Message{
        TopicPartition: kafka.TopicPartition{Topic: &topic},
        Headers:        headers,  // traceparent 헤더 포함
        Value:          value,
    }, nil)
}
```

### Consumer (Go)

```go
func consumeMessage(msg *kafka.Message) {
    // 헤더에서 트레이스 컨텍스트 추출
    carrier := propagation.MapCarrier{}
    for _, h := range msg.Headers {
        carrier[h.Key] = string(h.Value)
    }

    ctx := otel.GetTextMapPropagator().Extract(
        context.Background(),
        carrier,
    )

    // 추출된 컨텍스트로 새 스팬 시작
    tracer := otel.Tracer("kafka-consumer")
    ctx, span := tracer.Start(ctx, "process-message",
        trace.WithSpanKind(trace.SpanKindConsumer),
    )
    defer span.End()

    // 메시지 처리...
}
```

### 전파되는 헤더

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
tracestate: (optional vendor-specific data)
```

## Grafana에서 트레이스 조회

### Tempo 데이터소스 설정

```yaml
# Grafana datasource
- name: Tempo
  type: tempo
  url: http://tempo.observability:3200
  jsonData:
    tracesToLogsV2:
      datasourceUid: cloudwatch
      filterByTraceID: true
      filterBySpanID: true
    tracesToMetrics:
      datasourceUid: prometheus
      spanStartTimeShift: '-1h'
      spanEndTimeShift: '1h'
    serviceMap:
      datasourceUid: prometheus
    nodeGraph:
      enabled: true
```

### TraceQL 쿼리 예시

```
# 서비스별 트레이스 검색
{ resource.service.name = "order-service" }

# 에러 트레이스 검색
{ status = error }

# 특정 HTTP 경로의 느린 요청
{ span.http.route = "/api/v1/orders" && duration > 500ms }

# 특정 사용자의 트레이스
{ resource.user.id = "a0000001-0000-0000-0000-000000000001" }
```

## 트러블슈팅

### 트레이스가 수집되지 않을 때

```bash
# 1. OTel Collector 상태 확인
kubectl get pods -n platform -l app=otel-collector

# 2. Collector 로그 확인
kubectl logs -n platform -l app=otel-collector --tail=100

# 3. Tempo 상태 확인
kubectl get pods -n observability -l app=tempo

# 4. Tempo ready 확인
kubectl exec -n observability deploy/tempo -- wget -qO- http://localhost:3200/ready
```

### 샘플링 비율 조정

트래픽이 많은 경우 샘플링 비율을 조정합니다:

```yaml
tail_sampling:
  policies:
    - name: probabilistic-policy
      type: probabilistic
      probabilistic:
        sampling_percentage: 5  # 10% -> 5%로 감소
```

## 관련 문서

- [관측성 개요](./overview)
- [Prometheus 메트릭](./metrics-prometheus)
- [로깅](./logging)

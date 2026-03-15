# OpenTelemetry Distributed Tracing Design

## Overview

분산 트레이싱 파이프라인으로 multi-region shopping mall의 20개 마이크로서비스 간 요청 흐름을 추적한다. Grafana에서 trace view를 통합적으로 조회할 수 있도록 **Grafana Tempo**를 trace backend로 사용한다.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  EKS Cluster (per region)                                       │
│                                                                 │
│  ┌──────────┐   OTLP    ┌─────────────────────┐                │
│  │ App Pods │──────────▶│ OTel Collector      │                │
│  │ (20 svc) │  gRPC/HTTP│ (DaemonSet)         │                │
│  └──────────┘           │                     │                │
│                         │ • tail_sampling     │                │
│                         │ • batch             │                │
│                         │ • memory_limiter    │                │
│                         └──────┬──────┬───────┘                │
│                                │      │                        │
│                    ┌───────────┘      └──────────┐             │
│                    ▼                             ▼              │
│           ┌──────────────┐              ┌──────────────┐       │
│           │ Grafana Tempo│              │  AWS X-Ray   │       │
│           │ (Deployment) │              │  (managed)   │       │
│           └──────┬───────┘              └──────────────┘       │
│                  │                                              │
│                  ▼                                              │
│           ┌──────────────┐                                     │
│           │  S3 Bucket   │  ← trace blocks storage             │
│           │  (per region)│                                     │
│           └──────────────┘                                     │
│                                                                 │
│           ┌──────────────┐                                     │
│           │   Grafana    │  ← Tempo datasource                 │
│           │  (trace view)│  ← TraceQL queries                  │
│           └──────────────┘                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Backend Selection: Grafana Tempo

### 비교 분석

| 기준 | Grafana Tempo | ClickHouse | Jaeger + ES | AWS X-Ray |
|------|:---:|:---:|:---:|:---:|
| Grafana 네이티브 통합 | ✅ 완벽 | ⚠️ Plugin | ⚠️ Plugin | ❌ 별도 콘솔 |
| 운영 복잡도 | 낮음 (Stateless) | 높음 (StatefulSet) | 중간 | 없음 (Managed) |
| 월 비용 (per region) | ~$185 | ~$500+ | ~$400+ | ~$200 |
| TraceQL 지원 | ✅ 네이티브 | ❌ SQL | ❌ 자체 쿼리 | ❌ |
| Logs-to-Traces 연동 | ✅ 자동 | ⚠️ 수동 | ⚠️ 수동 | ❌ |
| Service Map | ✅ 자동 | ❌ | ⚠️ | ✅ |

### 선택 이유
1. **Grafana 네이티브**: TraceQL, service graph, logs-to-traces 상관관계가 한 화면에서 동작
2. **S3 백엔드**: StatefulSet 없이 S3에 trace block 저장 → 운영 부담 최소
3. **비용 효율**: $185/mo per region (전체 인프라 $44k 대비 0.4%)
4. **Dual-export**: 기존 X-Ray도 유지하여 AWS 네이티브 디버깅 도구 병행 사용

## Components

### 1. OTel Collector (기존 DaemonSet 업데이트)

**위치**: `k8s/infra/otel-collector/otel-collector.yaml`
**변경사항**: Tempo exporter 추가 + tail-based sampling 추가

```yaml
# Tail-based sampling 정책
tail_sampling:
  policies:
    - name: errors-policy          # 에러 100% 수집
      type: status_code
      status_code:
        status_codes: [ERROR]
    - name: slow-requests-policy   # 500ms 초과 100% 수집
      type: latency
      latency:
        threshold_ms: 500
    - name: probabilistic-policy   # 나머지 10% 샘플링
      type: probabilistic
      probabilistic:
        sampling_percentage: 10

# Dual export: Tempo + X-Ray
exporters:
  otlp/tempo:
    endpoint: tempo.observability:4317
    tls:
      insecure: true
  awsxray:
    region: ${AWS_REGION}
```

**Trace Pipeline**: `otlp → memory_limiter → tail_sampling → batch → [otlp/tempo, awsxray]`

### 2. Grafana Tempo (신규 Deployment)

**위치**: `k8s/infra/tempo/`
**모드**: Monolithic (단일 프로세스, 이 규모에 적합)
**저장소**: S3 (per-region bucket, KMS 암호화)

| 설정 | 값 |
|------|-----|
| Image | `grafana/tempo:2.6.1` |
| Replicas | 1 per region |
| CPU/Memory | 1 CPU / 2Gi |
| Block retention | 30일 (compactor) |
| S3 lifecycle | 30d → IA, 90d → Glacier, 365d expire |
| Metrics generator | service-graphs + span-metrics → Prometheus |

### 3. Grafana Datasource

**위치**: `k8s/infra/prometheus-stack/values.yaml`에 추가

```yaml
additionalDataSources:
  - name: Tempo
    type: tempo
    url: http://tempo.observability:3200
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
        filterByTraceID: true
      tracesToMetrics:
        datasourceUid: prometheus
      serviceMap:
        datasourceUid: prometheus
      nodeGraph:
        enabled: true
```

### 4. Application Instrumentation

OTel env vars는 이미 Kustomize overlay에서 모든 Deployment에 주입:

```yaml
# k8s/overlays/us-east-1/kustomization.yaml
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.platform.svc.cluster.local:4317"
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: OTEL_RESOURCE_ATTRIBUTES
          value: "deployment.environment=production,aws.region=us-east-1"
```

**언어별 Auto-instrumentation** (Dockerfile에서 설정):
| 언어 | 방법 |
|------|------|
| Java | `-javaagent:/otel/opentelemetry-javaagent.jar` |
| Python | `opentelemetry-instrument` wrapper |
| Go | Manual SDK init (`go.opentelemetry.io/otel`) |
| Node.js | `--require @opentelemetry/auto-instrumentations-node` |

## Terraform Resources

### Tempo S3 Storage Module

**위치**: `terraform/modules/observability/tempo-storage/`

| Resource | Purpose |
|----------|---------|
| `aws_s3_bucket.tempo` | Trace block 저장 |
| `aws_s3_bucket_lifecycle_configuration` | 30d IA → 90d Glacier → 365d expire |
| `aws_iam_role.tempo` | IRSA role for Tempo pods |
| `aws_iam_role_policy.tempo_s3` | S3 + KMS 권한 |

## File Inventory

| Action | Path | Description |
|--------|------|-------------|
| NEW | `terraform/modules/observability/tempo-storage/main.tf` | S3 + IRSA |
| NEW | `terraform/modules/observability/tempo-storage/variables.tf` | Variables |
| NEW | `terraform/modules/observability/tempo-storage/outputs.tf` | Outputs |
| NEW | `k8s/infra/tempo/kustomization.yaml` | Tempo kustomization |
| NEW | `k8s/infra/tempo/namespace.yaml` | observability namespace |
| NEW | `k8s/infra/tempo/tempo.yaml` | Tempo ConfigMap + Deployment + Service |
| MODIFY | `k8s/infra/otel-collector/otel-collector.yaml` | Add Tempo exporter + tail sampling |
| MODIFY | `k8s/infra/prometheus-stack/values.yaml` | Add Tempo datasource |
| MODIFY | `k8s/infra/kustomization.yaml` | Add tempo |
| MODIFY | `k8s/infra/argocd/apps/appset-infra.yaml` | Add otel-collector, tempo |
| MODIFY | `terraform/environments/production/*/main.tf` | Add tempo_storage module |

## Cost Estimate (per region)

| Component | Monthly Cost |
|-----------|-------------|
| Tempo S3 storage (100GB/mo) | ~$25 |
| S3 API calls | ~$50 |
| OTel Collector (DaemonSet, EKS nodes) | ~$50 |
| Tempo pod (1 CPU, 2Gi) | ~$60 |
| **Total** | **~$185/mo** |

**Both regions**: ~$370/mo (전체 인프라 $44,250/mo의 0.8%)

## Observability Flow

```
User Request → API Gateway → Service A → Service B → Database
     │              │             │            │          │
     └──────────────┴─────────────┴────────────┴──────────┘
                              │
                    OTEL_EXPORTER_OTLP_ENDPOINT
                              │
                    ┌─────────▼──────────┐
                    │   OTel Collector   │
                    │  (tail sampling)   │
                    └────────┬───────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         Tempo (S3)     X-Ray          Prometheus
              │                            │
              └────────────┬───────────────┘
                           ▼
                    ┌──────────────┐
                    │   Grafana    │
                    │              │
                    │ • Trace View │ ← TraceQL 쿼리
                    │ • Service Map│ ← 서비스 의존성 그래프
                    │ • Logs→Trace │ ← traceID로 로그 연동
                    │ • Metrics    │ ← span에서 생성된 RED metrics
                    └──────────────┘
```

## Grafana에서 Trace 조회 방법

1. **Explore → Tempo**: TraceQL로 trace 검색
   - `{ resource.service.name = "product-catalog" && status = error }`
   - `{ duration > 500ms && resource.service.name = "order-service" }`

2. **Service Map**: Tempo metrics_generator가 자동 생성한 service graph

3. **Logs → Traces**: 로그에 포함된 traceID 클릭 → Tempo trace view 자동 연결

4. **Dashboard**: span-metrics에서 생성된 RED metrics로 대시보드 구성

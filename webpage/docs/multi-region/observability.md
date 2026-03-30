---
sidebar_position: 7
title: Observability
description: OTel Collector, ClickHouse, Tempo, Prometheus, Grafana
---

# Observability Stack

## Unified Pipeline Overview

```
                    ┌─────────────────┐
                    │  OTel Collector  │
                    │ contrib v0.115.0 │
                    │   (DaemonSet)    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
         │ Traces  │   │  Logs   │   │ Metrics │
         └────┬────┘   └────┬────┘   └────┬────┘
              │              │              │
    ┌─────────┤         ┌────┤              │
    │         │         │    │              │
┌───▼───┐ ┌──▼──┐ ┌───▼──┐ ┌▼────────┐ ┌──▼────────┐
│ Click │ │Tempo│ │X-Ray │ │CW Logs  │ │Prometheus │
│ House │ │     │ │      │ │         │ │           │
└───┬───┘ └──┬──┘ └──────┘ └─────────┘ └──┬────────┘
    │        │                              │
    └────────┴──────────┬───────────────────┘
                   ┌────▼────┐
                   │ Grafana │
                   └─────────┘
```

## OTel Collector

| 속성 | 값 |
|------|-----|
| Image | OTel Collector Contrib `v0.115.0` |
| Deployment | DaemonSet (Kustomize + Helm ApplicationSet) |
| IRSA | `production-otel-collector-[region]` |

### Receivers

- **OTLP**: gRPC (`:4317`), HTTP (`:4318`)
- **filelog**: 컨테이너 로그 수집 (FluentBit 대체)
- **k8s_events**: Kubernetes 이벤트

### Processors

- **batch**: 배치 처리로 효율 향상
- **k8sattributes**: Pod metadata 자동 첨부
- **spanmetrics connector**: span에서 metric 생성 (exemplar with `trace_id`)

### Exporters

| Signal | Destinations |
|--------|-------------|
| **Traces** | ClickHouse + Tempo + AWS X-Ray (3중 출력) |
| **Logs** | ClickHouse + CloudWatch Logs |
| **Metrics** | Prometheus (via spanmetrics) |

## ClickHouse

| 속성 | 값 |
|------|-----|
| Operator | Altinity ClickHouse Operator `v0.24.1` |
| Server | `clickhouse-server:24.8` |
| Topology | 1 shard / 1 replica |
| Storage | 50Gi gp3 |
| Namespace | `observability` |
| Endpoint | `clickhouse-clickhouse.observability:9000` (tcp) / `:8123` (http) |

### Schema

| Table | Engine | TTL |
|-------|--------|-----|
| `otel.otel_traces` | MergeTree | 30 days |
| `otel.otel_logs` | MergeTree | 30 days |

## Tempo

| 속성 | 값 |
|------|-----|
| Version | `v2.6.1` monolithic mode |
| Backend | S3 (IRSA + 전용 버킷) |
| tracesToLogs | ClickHouse datasource (filterByTraceID + filterBySpanID) |
| Config | `$VAR` expansion via `-config.expand-env=true` |

:::caution Tempo 주의사항
- Tempo ConfigMap은 `${VAR}` 환경변수 확장을 사용 — Pod에 env var 설정 필수
- Tempo AppSet이 kustomization.yaml에 누락되기 쉬움 — 확인 필요
:::

## Prometheus + Grafana

| 속성 | 값 |
|------|-----|
| Stack | kube-prometheus-stack Helm `v68.4.0` |
| Exemplars | `exemplar-storage` enabled |
| Grafana Plugins | `grafana-clickhouse-datasource` |
| Datasources | Prometheus, ClickHouse, Tempo |

### Exemplar Flow

```
Metric graph → Click exemplar point → Trace in ClickHouse → Correlated logs
```

`exemplarTraceIdDestinations`가 ClickHouse datasource를 가리키고, Tempo의 `tracesToLogs`도 ClickHouse를 참조하여 metric → trace → log 전체 연결을 달성합니다.

:::note StorageClass 주의
Prometheus StatefulSet의 VolumeClaimTemplate은 **immutable**입니다. `storageClassName` 변경 시 STS + PVC를 삭제 후 재생성해야 합니다. Grafana PVC는 standalone PVC(Deployment)로 별도 관리.
:::

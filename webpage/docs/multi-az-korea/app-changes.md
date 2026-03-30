---
sidebar_position: 9
title: Application Changes
description: AZ-Local 접근을 위한 환경변수, 코드 변경, Observability
---

# Application Changes

## New Environment Variables

| Variable | 용도 | 예시 (AZ-A) |
|----------|------|-------------|
| `AVAILABILITY_ZONE` | 현재 AZ 식별 | `ap-northeast-2a` |
| `CLIENT_RACK` | Kafka rack-aware 소비 | `ap-northeast-2a` |
| `DB_WRITE_HOST` | Aurora Writer endpoint | Cluster writer endpoint |
| `DB_READ_HOST_LOCAL` | Aurora AZ-local reader | Custom EP: reader-az-a |
| `PREFER_REPLICA_AZ` | ElastiCache AZ preference | `ap-northeast-2a` |
| `DOCUMENTDB_HOST` | DocumentDB AZ-local instance | AZ-A instance endpoint |
| `KAFKA_BROKERS_LOCAL` | 로컬 AZ MSK 브로커 | AZ-A broker endpoints |

## AZ-Local Access Patterns

### Go Services

```go
// ElastiCache — RouteByLatency
client := redis.NewClusterClient(&redis.ClusterOptions{
    RouteByLatency: true,  // 자연스럽게 같은 AZ replica 선호
})

// Kafka — RackAffinityGroupBalancer
reader := kafka.NewReader(kafka.ReaderConfig{
    GroupBalancers: []kafka.GroupBalancer{
        kafka.RackAffinityGroupBalancer{
            Rack: os.Getenv("CLIENT_RACK"),  // "ap-northeast-2a"
        },
    },
})

// Aurora — AZ-local reader fallback
readHost := os.Getenv("DB_READ_HOST_LOCAL")
if readHost == "" {
    readHost = os.Getenv("DB_HOST")  // US 리전 fallback
}
```

### Python Services

```python
# ElastiCache — read_from_replicas
client = RedisCluster(
    read_from_replicas=True,  # 로컬 AZ replica 자동 선호
)

# DocumentDB — AZ-local instance EP
client = motor.AsyncIOMotorClient(
    os.environ["DOCUMENTDB_HOST"],  # AZ별 instance endpoint
    # 기존 cluster endpoint 대신 개별 instance EP 사용
)

# Kafka — KAFKA_BROKERS_LOCAL
brokers = os.environ.get("KAFKA_BROKERS_LOCAL",
                         os.environ.get("KAFKA_BROKERS"))
```

### Java Services

```java
// ElastiCache — ReadFrom.NEAREST
@Bean
LettuceClientConfiguration clientConfig() {
    return LettuceClientConfiguration.builder()
        .readFrom(ReadFrom.NEAREST)  // AZ-local replica 자동 선택
        .build();
}

// Kafka — client.rack
props.put("client.rack",
    System.getenv("CLIENT_RACK"));  // "ap-northeast-2a"
```

## Backward Compatibility

모든 새 환경변수에 **기본값 fallback**을 설정하여, 한국 리전 이외(US)에서는 기존 동작을 유지합니다.

```go
// Go example — 모든 새 환경변수에 fallback
readHost := os.Getenv("DB_READ_HOST_LOCAL")
if readHost == "" {
    readHost = os.Getenv("DB_HOST")  // 기존 환경변수로 fallback
}

kafkaBrokers := os.Getenv("KAFKA_BROKERS_LOCAL")
if kafkaBrokers == "" {
    kafkaBrokers = os.Getenv("KAFKA_BROKERS")  // 기존 환경변수로 fallback
}
```

:::tip 하위 호환성 원칙
1. 새 환경변수 미설정 시 → 기존 환경변수 사용
2. 기존 환경변수도 미설정 시 → 하드코딩된 기본값 또는 graceful degradation
3. US 리전에서는 새 환경변수를 설정하지 않으므로 기존 동작 유지
:::

## Observability

각 AZ 클러스터에 독립 OTel Collector DaemonSet이 배포됩니다. `OTEL_RESOURCE_ATTRIBUTES`에 `aws.zone`을 포함하여 trace/log에서 AZ 식별이 가능합니다.

| Component | AZ-A | AZ-C |
|-----------|------|------|
| OTel Collector | DaemonSet (IRSA: apne2-az-a) | DaemonSet (IRSA: apne2-az-c) |
| Tempo | S3 backend (IRSA per cluster) | S3 backend (IRSA per cluster) |
| Prometheus | kube-prometheus-stack (korea AppSet) | kube-prometheus-stack |
| Resource Attr | `aws.zone=ap-northeast-2a` | `aws.zone=ap-northeast-2c` |

### OTel Resource Attributes

```yaml
OTEL_RESOURCE_ATTRIBUTES: "deployment.environment=production,aws.region=ap-northeast-2,aws.zone=ap-northeast-2a"
```

이 attribute가 모든 trace, log, metric에 자동으로 첨부되어 Grafana에서 AZ별 필터링이 가능합니다.

## 코드 변경 요약

| 영역 | 변경 파일 | 설명 |
|------|-----------|------|
| Go shared | `pkg/config/config.go` | `DB_READ_HOST_LOCAL`, `KAFKA_BROKERS_LOCAL` fallback |
| Go shared | `pkg/kafka/consumer.go` | `RackAffinityGroupBalancer` 추가 |
| Python shared | `mall_common/config.py` | `DB_READ_HOST_LOCAL` fallback |
| Python shared | `mall_common/kafka.py` | `KAFKA_BROKERS_LOCAL` fallback |
| Java shared | `application.yml` | `client.rack`, `ReadFrom.NEAREST` |
| K8s overlay | `az-a/kustomization.yaml` | AVAILABILITY_ZONE, CLIENT_RACK 주입 |
| K8s overlay | `az-c/kustomization.yaml` | 동일 (AZ-C 값) |

---
sidebar_position: 8
title: K8s Overlays
description: AZ별 Kustomize overlay, ArgoCD 통합, ConfigMap
---

# K8s Overlays

## Directory Structure

```
k8s/overlays/ap-northeast-2/
├── common/                           # 리전 공통 패치 (DRY)
│   ├── region-config-patch.yaml     # AWS_REGION, OTEL_ENDPOINT
│   └── common-labels.yaml           # region: ap-northeast-2
│
├── az-a/                              # AZ-A overlay
│   ├── kustomization.yaml           # base + services + infra + AZ patches
│   ├── karpenter/
│   │   └── ec2nodeclass.yaml        # zone: ap-northeast-2a only
│   ├── core/kustomization.yaml
│   ├── user/kustomization.yaml
│   ├── fulfillment/kustomization.yaml
│   ├── business/kustomization.yaml
│   └── platform/kustomization.yaml
│
└── az-c/                              # AZ-C overlay (mirror of az-a)
    ├── kustomization.yaml           # base + services + infra + AZ patches
    ├── karpenter/
    │   └── ec2nodeclass.yaml        # zone: ap-northeast-2c only
    └── ...
```

## Per-AZ Overlay (kustomization.yaml)

각 AZ overlay는 두 가지 핵심 패치를 적용합니다.

### 1. AZ 환경변수 주입

모든 Deployment에 AZ 식별용 환경변수를 주입합니다:

```yaml
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: AVAILABILITY_ZONE
          value: "ap-northeast-2a"
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: CLIENT_RACK
          value: "ap-northeast-2a"
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.platform.svc.cluster.local:4317"
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: OTEL_RESOURCE_ATTRIBUTES
          value: "deployment.environment=production,aws.region=ap-northeast-2,aws.zone=ap-northeast-2a"
```

### 2. TopologySpreadConstraints 제거

단일 AZ 클러스터에서 TSC(cross-AZ 분산)는 불필요하므로 제거합니다:

```yaml
  - target:
      kind: Deployment
    patch: |-
      - op: remove
        path: /spec/template/spec/topologySpreadConstraints
```

:::tip TSC 제거 이유
base의 Deployment에 정의된 `topologySpreadConstraints`는 cross-AZ 분산을 위한 것입니다. 단일 AZ 클러스터에서는 모든 노드가 같은 AZ에 있으므로 이 제약이 의미가 없고, 오히려 Pod 스케줄링을 방해할 수 있습니다.
:::

## ConfigMap Generator

각 AZ overlay에서 `region-config` ConfigMap을 생성합니다:

```yaml
configMapGenerator:
  - name: region-config
    namespace: platform
    literals:
      - REGION=ap-northeast-2
      - AZ=ap-northeast-2a                    # AZ-C에서는 ap-northeast-2c
      - REGION_ROLE=PRIMARY
      - MSK_BROKERS=placeholder               # Terraform 후 실제 엔드포인트로 교체
      - VALKEY_ENDPOINT=placeholder
      - DOCUMENTDB_ENDPOINT=placeholder
      - OPENSEARCH_ENDPOINT=placeholder
```

| Key | AZ-A | AZ-C |
|-----|------|------|
| `REGION` | ap-northeast-2 | ap-northeast-2 |
| `AZ` | ap-northeast-2a | ap-northeast-2c |
| `REGION_ROLE` | PRIMARY | PRIMARY |
| `MSK_BROKERS` | Terraform 적용 후 실제 엔드포인트 | 동일 |
| `VALKEY_ENDPOINT` | placeholder (교체 필요) | 동일 |
| `DOCUMENTDB_ENDPOINT` | AZ-A instance EP | AZ-C instance EP |

## Common Labels

```yaml
commonLabels:
  region: ap-northeast-2
  az: ap-northeast-2a          # AZ-C에서는 ap-northeast-2c
```

## ArgoCD Integration

ArgoCD ApplicationSet의 `generators.clusters`에서 클러스터 라벨로 overlay 디렉토리를 매칭합니다.

```yaml
# ApplicationSet generator example
generators:
  - clusters:
      selector:
        matchLabels:
          region: ap-northeast-2
          az: ap-northeast-2a
      values:
        overlay: ap-northeast-2/az-a
```

각 AZ EKS 클러스터를 ArgoCD에 등록하면 자동으로 해당 overlay가 적용됩니다.

:::info Korea-specific AppSet
Prometheus 등 Helm 차트는 리전별 커스텀이 필요하여 `appset-helm-prometheus-korea.yaml`이 별도 생성되었습니다.
:::

## US 리전 Overlay와의 비교

| 항목 | US Overlays | Korea Overlays |
|------|-------------|----------------|
| 경로 | `k8s/overlays/us-east-1/`, `us-west-2/` | `k8s/overlays/ap-northeast-2/az-a/`, `az-c/` |
| 레벨 | 리전별 | AZ별 |
| 공통 패치 | 없음 (각 리전 독립) | `common/` 디렉토리 (DRY) |
| TSC | 유지 (multi-AZ 분산) | 제거 (single-AZ) |
| AZ 환경변수 | 없음 | AVAILABILITY_ZONE, CLIENT_RACK |
| Karpenter | multi-AZ 서브넷 | single-AZ 서브넷 (zone 태그) |

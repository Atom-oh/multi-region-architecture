---
sidebar_position: 3
title: Design Decisions
description: 4-AI 비교 분석을 통한 최적 설계 선택
---

# Design Decisions

4개 AI(Claude, Codex, Gemini, Kiro-CLI)에게 동일한 요구사항으로 한국 리전 Multi-AZ 아키텍처 설계를 요청하고, 결과를 7개 축으로 비교 분석하여 최종 구현 방향을 결정했습니다.

## 최종 설계 선택

| 영역 | 선택 | 출처 | 근거 |
|------|------|------|------|
| **TF 구조** | 3-layer (shared + eks-az-a + eks-az-c) | Claude/Kiro | 기존 패턴 일관성, 운영 단순 |
| **VPC 서브넷** | /20 Private (4,096 IPs) | Codex | Karpenter 노드 스케일링 대비 |
| **EKS 이름** | `mall-apne2-az-a` / `mall-apne2-az-c` | Kiro | 간결 + 리전/AZ 식별 |
| **Karpenter AZ 고정** | 서브넷 태그 + NodePool zone (이중 안전장치) | Kiro | AZ 격리 보장 |
| **MSK** | 4 brokers + KAFKA_BROKERS_LOCAL | Codex | 가용성 + Go/Python AZ locality |
| **Aurora** | 1W + 2R + Custom Endpoint per AZ | Claude/Kiro | 균형적 AZ 배치 |
| **ElastiCache** | RouteByLatency + PREFER_REPLICA_AZ | Kiro | 최소 코드 변경 |
| **DocumentDB** | 개별 Instance Endpoint | Kiro | Custom EP 미지원 대응 (유일 정답) |
| **K8s overlay** | common/ + az-a/ + az-c/ | Codex | DRY 원칙 |
| **앱 코드** | 상세 코드 + 명시적 환경변수 | Kiro + Codex | 구현 가이드 + 명시성 |

## 합의 사항 (4/4 일치)

모든 AI가 동의한 핵심 설계:

- VPC CIDR: `10.2.0.0/16`
- Terraform 레이어 분리: shared(VPC+Data) → EKS per AZ
- EKS 2개 클러스터: AZ-A 전용 + AZ-C 전용
- Aurora Custom Endpoint: AZ별 reader endpoint
- MSK `client.rack`: AZ-local 소비
- K8s overlay: AZ별 디렉토리 분리
- TopologySpreadConstraints 제거 (단일 AZ)

## 주요 결정 근거

### Terraform: 3-layer vs 5-layer

| AI | 레이어 수 | Network 분리 | State 키 수 |
|----|-----------|-------------|------------|
| Claude | 3 | shared에 포함 | 3 |
| **Codex** | **5** | **별도 network/ 레이어** | **5** |
| Gemini | 4 | 별도 networking/ | 4 |
| Kiro | 3 | shared에 포함 | 3 |

**선택: 3-layer** — Codex의 5-layer는 대규모 팀에서 유리하나, 이 프로젝트에서는 오버엔지니어링. 기존 Multi-Region 패턴과의 일관성을 위해 3-layer 채택.

### VPC Private Subnet: /24 vs /20

| AI | Private 서브넷 크기 |
|----|---------------------|
| Claude | /24 (256 IPs) |
| **Codex** | **/20 (4,096 IPs)** |
| **Gemini** | **/20 (4,096 IPs)** |
| Kiro | /24 (256 IPs) |

**선택: /20** — Karpenter가 단일 AZ 내에서만 노드를 프로비저닝하므로 충분한 IP 공간이 필요합니다. /24(256 IPs)에서는 노드 ~50개 미만으로 제한됩니다.

### DocumentDB: Custom EP vs Instance EP

| AI | 접근 방식 | 올바름? |
|----|-----------|---------|
| Claude | readPreference nearest | 부분적 |
| Codex | 공유 endpoint | 부분적 |
| Gemini | Aurora와 동일 | 오류 |
| **Kiro** | **개별 instance endpoint** | **정확** |

**선택: Instance EP** — DocumentDB는 Aurora와 달리 Custom Endpoint를 지원하지 않습니다. Kiro만 이 제약을 정확히 인지했습니다.

### MSK Broker Count: 2 vs 4

| AI | 브로커 수 | 환경변수 |
|----|-----------|----------|
| Claude | 2 (1+1) | KAFKA_BROKERS (공유) |
| **Codex** | **4 (2+2)** | **KAFKA_BROKERS_LOCAL + FALLBACK** |
| Gemini | 2 (1+1) | KAFKA_BROKERS (공유) |
| Kiro | 3 | KAFKA_BROKERS + CLIENT_RACK |

**선택: 4 brokers** — MSK `number_of_broker_nodes`는 AZ 수의 배수여야 합니다. 2 AZ에서 4(2+2)가 가용성과 처리량에서 유리. Codex의 `KAFKA_BROKERS_LOCAL` 패턴으로 rack-aware가 안 되는 Go/Python에서도 AZ locality를 확보합니다.

## AI별 종합 평가

| 평가 축 | Claude | Codex | Gemini | Kiro-CLI |
|---------|--------|-------|--------|----------|
| 구조 설계 | ★★★★ | ★★★★★ | ★★★ | ★★★★ |
| 코드 상세도 | ★★★ | ★★★★ | ★★ | ★★★★★ |
| 비용 분석 | ★★ | ★★★★★ | ★★★★ | ★★ |
| AWS 제약 인지 | ★★★★ | ★★★★ | ★★★ | ★★★★★ |
| 실행 가능성 | ★★★★ | ★★★ | ★★★★ | ★★★★★ |
| 기존 패턴 일관성 | ★★★★★ | ★★★ | ★★ | ★★★★ |
| **종합** | **4.0** | **3.8** | **3.0** | **4.2** |

:::info 핵심 차별점
- **Codex**: 가장 세밀한 비용/구조 분석. KAFKA_BROKERS_LOCAL/FALLBACK 패턴이 독창적
- **Gemini**: 간결한 설계. DocumentDB Custom EP 미지원 인지 실패
- **Kiro-CLI**: 코드베이스를 실제로 읽고 가장 구체적인 코드 변경 제시. RackAffinityGroupBalancer 발견
- **Claude**: 기존 코드와의 일관성 최우선. MSK Go rack-aware 포기가 약점
:::

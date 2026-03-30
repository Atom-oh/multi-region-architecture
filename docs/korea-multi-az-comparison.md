# Korea Multi-AZ Architecture Design Comparison

**Date**: 2026-03-29
**Region**: ap-northeast-2 (Seoul)
**Objective**: AZ-A / AZ-C 분리 EKS 클러스터 + AZ-local 데이터 접근

---

## Executive Summary

4개 AI(Claude, Codex, Gemini, Kiro-CLI)에게 동일한 요구사항으로 한국 리전 Multi-AZ 아키텍처 설계를 요청하고, 결과를 7개 축으로 비교 분석하였다. **핵심 합의점**과 **차이점**을 도출하여 최종 구현 방향을 결정한다.

### 합의된 사항 (4/4 일치)
- VPC CIDR: `10.2.0.0/16`
- Terraform 레이어 분리: shared(VPC+Data) → EKS per AZ
- EKS 2개 클러스터: AZ-A 전용 + AZ-C 전용
- Aurora Custom Endpoint: AZ별 reader endpoint
- MSK `client.rack`: AZ-local 소비
- K8s overlay: AZ별 디렉토리 분리
- TopologySpreadConstraints 제거 (단일 AZ)

---

## 1. Terraform Folder Structure

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **레이어 수** | 3 (shared, eks-az-a, eks-az-c) | 5 (network, shared-data, eks-az-a, eks-az-c, edge) | 4 (networking, data-shared, eks-aza, eks-azc) | 3 (shared, az-a, az-c) |
| **Network 분리** | shared에 포함 | 별도 network/ 레이어 | 별도 networking/ | shared에 포함 |
| **Edge 분리** | 없음 | 별도 edge/ 레이어 | 없음 | 없음 |
| **State 키 수** | 3 | 5 | 4 | 3 |

### 분석
- **Codex**가 가장 세분화 (5-layer). Network/Edge 분리는 대규모 팀에서 유리하나 이 프로젝트에서는 오버엔지니어링.
- **Claude/Kiro** 3-layer가 기존 multi-region 패턴과 가장 유사하고 운영 복잡도가 낮음.
- **Gemini** 4-layer는 중간 지점이나 ap-northeast-2/ 하위에 production/ 레벨이 없어 기존 패턴과 불일치.

**최적**: 3-layer (Claude/Kiro 방식) — `shared/`, `eks-az-a/`, `eks-az-c/`

---

## 2. VPC CIDR Allocation

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **VPC** | 10.2.0.0/16 | 10.2.0.0/16 | 10.2.0.0/16 | 10.2.0.0/16 |
| **Private 서브넷** | /24 (256 IPs) | **/20 (4,096 IPs)** | **/20 (4,096 IPs)** | /24 (256 IPs) |
| **AZ-B 예약** | 번호대 비움 | 명시적 Reserved 블록 | 없음 | 없음 |
| **Public** | 10.2.1,3.0/24 | 10.2.0,1.0/24 | 10.2.0,1.0/24 | 10.2.1,2.0/24 |
| **Data** | 10.2.21,23.0/24 | 10.2.64,65.0/24 | 10.2.42,43.0/24 | 10.2.21,22.0/24 |

### 분석
- **서브넷 크기**: /24(256 IPs) vs /20(4,096 IPs). Karpenter가 노드를 동적 프로비저닝하므로 **최소 /19~20** 권장. /24는 노드 50개 미만으로 제한됨.
- **Codex**의 Reserved 블록 패턴이 가장 확장 친화적.
- **Claude/Kiro**의 /24는 프로덕션에 부족할 수 있음.

**최적**: Codex 방식의 /20 Private + Reserved 블록, 단 기존 패턴과의 일관성을 위해 번호 체계는 Claude/Kiro 방식 유지

---

## 3. EKS Cluster Configuration

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **이름 규칙** | mall-korea-az-a/c | production-apne2-eks-a/c | mall-kr-aza/c | mall-apne2-az-a/c |
| **Bootstrap 인스턴스** | t3.medium | m7i.large | c7g/r7g (Graviton3) | m7g/m7i.large |
| **Karpenter AZ 고정** | 서브넷 태그 (kubernetes.io/az) | zone 요구사항 + discovery 태그 | NodePool zone 제약 | 서브넷 태그 (topology.kubernetes.io/zone) + NodePool zone 제약 |
| **아키텍처** | amd64 only | amd64 | **arm64 우선 (Graviton3)** | arm64 + amd64 |

### 분석
- **이름 규칙**: `mall-apne2-az-a` (Kiro)가 간결하면서도 리전+AZ 식별 가능. 기존 `multi-region-mall`과는 다른 패턴이므로 한국 전용 네이밍.
- **Graviton3**: Gemini/Kiro의 arm64 제안은 비용 최적화에 유리 (최대 40% 절감). 단, 기존 코드베이스가 amd64-only이므로 이미지 멀티아키텍처 빌드 필요.
- **Karpenter AZ 고정**: Kiro 방식(서브넷 태그 + NodePool zone 제약, 이중 안전장치)이 가장 견고.

**최적**: Kiro 이름 규칙 + Kiro 이중 AZ 고정 + amd64 우선 (arm64는 Phase 2)

---

## 4. Data Store AZ Strategy

### 4-1. MSK

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **브로커 수** | 2 (1+1) | **4 (2+2)** | 2 (1+1) | **3** |
| **rack-aware** | client.rack (Java only) | client.rack + local/fallback brokers | client.rack | client.rack (CLIENT_RACK env) |
| **env 변수** | KAFKA_BROKERS (공유) | **KAFKA_BROKERS_LOCAL + FALLBACK** | KAFKA_BROKERS (공유) | KAFKA_BROKERS (공유) + CLIENT_RACK |

### 분석
- **브로커 수**: MSK는 `number_of_broker_nodes`가 AZ 수의 배수여야 함. 2 AZ면 최소 2, 권장 4(2+2). Codex의 4 브로커가 가용성과 처리량에서 유리.
- **Kiro의 3**: 2 AZ에서 3은 불균등 배치 (2+1). 비권장.
- **Codex의 KAFKA_BROKERS_LOCAL**: 앱이 로컬 AZ 브로커만 우선 사용 — rack-aware가 안 되는 Go/Python에서도 AZ locality 확보 가능. 가장 실용적.

**최적**: Codex 방식 — 4 brokers + KAFKA_BROKERS_LOCAL/FALLBACK

### 4-2. Aurora

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **인스턴스** | 1W + 2R | 1W + 2R | 1W(A) + 1R(C) | 1W + 2R (1A+1C) |
| **Custom Endpoint** | reader_az_a, reader_az_c | aurora-ro-2a, aurora-ro-2c | ep-reader-aza, ep-reader-azc | reader-az-a, reader-az-c |
| **Writer 환경변수** | DB_HOST(writer) + DB_READ_HOST(reader) | DB_WRITE_HOST + DB_READ_HOST_LOCAL | writer-endpoint(공유) | DB_WRITER_HOST + DB_HOST(reader) |
| **Read/Write 분리** | 앱 코드에서 분기 | **AbstractRoutingDataSource (Java)** | 앱 코드에서 분기 | 앱 코드에서 분기 |

### 분석
- 4개 모두 Aurora Custom Endpoint 사용에 합의.
- **Codex**의 `AbstractRoutingDataSource`는 Java 서비스에서 트랜잭션 읽기전용 여부로 자동 라우팅 — 가장 정교하지만 구현 복잡.
- **Gemini**의 1W+1R은 AZ-A에 reader가 없어 AZ-A 클러스터가 writer에 직접 읽기 → 성능 저하.
- **Claude/Kiro** 1W+2R이 가장 균형적.

**최적**: Claude/Kiro 방식 (1W+2R) + Codex의 환경변수 네이밍 (DB_WRITE_HOST, DB_READ_HOST_LOCAL)

### 4-3. ElastiCache

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **AZ-local 읽기** | RouteByLatency (go-redis) | CACHE_REPLICA_HOST_LOCAL | Primary(A)+Replica(C) endpoint 분리 | PREFER_REPLICA_AZ + read_from_replicas |
| **Go** | RouteByLatency: true | 별도 read/write client | RouteByLatency | RouteByLatency |
| **Python** | read_from_replicas=True | 별도 read/write client | N/A | read_from_replicas=True |
| **Java** | ReadFrom.NEAREST | 별도 ConnectionFactory | ReadFrom.NEAREST | ReadFrom.NEAREST |

### 분석
- **Codex**의 별도 read/write client 접근은 가장 확실하지만 앱 코드 변경량이 큼.
- **Kiro**의 PREFER_REPLICA_AZ + 클라이언트 옵션 조합이 기존 코드 변경을 최소화하면서도 효과적.
- `RouteByLatency`는 같은 AZ replica를 자연스럽게 선호 — 추가 코드 불필요.

**최적**: Kiro 방식 (PREFER_REPLICA_AZ) + Claude의 RouteByLatency/ReadFrom.NEAREST

### 4-4. DocumentDB

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **접근 방식** | readPreference nearest | 공유 endpoint | Aurora와 동일 | **개별 instance endpoint** |

### 분석
- DocumentDB는 Aurora와 달리 **Custom Endpoint를 지원하지 않음**. Kiro만 이 제약을 정확히 인지.
- **Kiro 방식**(개별 instance endpoint 직접 주입)이 유일하게 올바른 접근.

**최적**: Kiro 방식 — 개별 instance endpoint를 DOCUMENTDB_HOST에 AZ별로 주입

---

## 5. K8s Overlay Structure

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **디렉토리** | ap-northeast-2a/, ap-northeast-2c/ | ap-northeast-2/common/ + az-a/ + az-c/ | ap-northeast-2-aza/, ap-northeast-2-azc/ | ap-northeast-2-az-a/, ap-northeast-2-az-c/ |
| **공통 base** | 없음 (각각 독립) | **common/ 디렉토리** | 없음 | 없음 |
| **TSC 제거** | overlay patch | overlay patch | overlay patch | overlay patch (JSON6902) |

### 분석
- **Codex**의 `common/` 디렉토리로 공유 패치 관리가 DRY 원칙에 가장 부합. 리전 공통 설정(region-config, common-labels)을 한 곳에서 관리.
- **Kiro**의 JSON6902 patch로 topologySpreadConstraints 제거가 가장 명시적.
- ArgoCD ApplicationSet은 overlay 디렉토리명을 cluster label과 매칭하므로, 디렉토리명은 짧고 일관적이어야 함.

**최적**: Codex 방식(common/ 공유) + Kiro 방식(JSON6902 TSC 제거)

---

## 6. Application Code Changes

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **새 환경변수 수** | 2 (DB_READ_HOST, NODE_AZ) | **6+** (DB_WRITE_HOST, DB_READ_HOST_LOCAL, CACHE_PRIMARY_HOST, CACHE_REPLICA_HOST_LOCAL, KAFKA_BROKERS_LOCAL, KAFKA_BROKERS_FALLBACK) | 2 (DATABASE_READER_URL, AZ_ID) | 4 (DB_WRITER_HOST, CLIENT_RACK, PREFER_REPLICA_AZ, AVAILABILITY_ZONE) |
| **코드 변경 범위** | 최소 (4 파일) | 대규모 (10+ 파일) | 중간 (6 파일) | **중간-상세 (8 파일, 코드 예시 포함)** |
| **하위 호환성** | 기본값 fallback | 기본값 fallback | 프로파일 분리 | **기본값 fallback** |
| **Go kafka rack** | 지원 불가 언급 | Sarama/Confluent 마이그레이션 제안 | N/A | **RackAffinityGroupBalancer 코드 제시** |

### 분석
- **Kiro**가 가장 상세한 코드 예시 제공 (Go/Python/Java 모두). `RackAffinityGroupBalancer` 사용은 kafka-go에서 rack-aware를 가능하게 하는 구체적 방법.
- **Codex**의 환경변수 체계가 가장 명시적이지만 변경 범위가 크고 기존 서비스와의 호환성 고려 필요.
- **Claude**는 변경 최소화를 우선했으나 MSK rack-aware를 Go에서 포기한 점이 약점.

**최적**: Kiro의 코드 예시 + Codex의 환경변수 네이밍 (단, 필수 최소한으로 축소)

---

## 7. Cost Analysis

| 항목 | Claude | Codex | Gemini | Kiro-CLI |
|------|--------|-------|--------|----------|
| **EKS 추가 비용** | 언급 없음 | $73/월 per cluster | **$72/월 per cluster** | 언급 없음 |
| **Cross-AZ 절감** | 언급 없음 | 읽기 부하 의존 | **$500~2,000/월** | 언급 없음 |
| **총 비용 영향** | 미산출 | **+4~12% (데이터 포함), +12~25% (컴퓨트만)** | 트래픽 많을수록 유리 | 미산출 |
| **대안 제시** | 없음 | single cluster + topology-aware scheduling | 없음 | 없음 |

### 분석
- **Gemini**가 가장 직관적인 비용 비교 (테이블).
- **Codex**가 가장 현실적인 TCO 분석 (+4~12%). 또한 "read-heavy가 아니면 single cluster가 cost-efficient"라는 중요한 트레이드오프를 제시.
- Cross-AZ 데이터 전송 비용 ($0.01/GB)과 EKS 추가 비용 ($73/월) 간의 손익분기점: 약 7.3TB/월 이상의 cross-AZ 트래픽이 있어야 2-cluster가 유리.

---

## 최종 설계 선택

각 영역별 최적 접근을 조합한 **통합 설계**:

| 영역 | 선택 | 근거 |
|------|------|------|
| **TF 구조** | 3-layer (Claude/Kiro) | 기존 패턴 일관성, 운영 단순 |
| **VPC 서브넷** | /20 (Codex) + 기존 번호 체계 | Karpenter 노드 스케일링 대비 |
| **EKS 이름** | mall-apne2-az-a/c (Kiro) | 간결 + 리전/AZ 식별 |
| **Karpenter AZ** | 이중 고정 (Kiro) | 서브넷 태그 + NodePool zone |
| **MSK** | 4 brokers + LOCAL/FALLBACK (Codex) | 가용성 + Go/Python AZ locality |
| **Aurora** | 1W+2R + Custom EP (Claude/Kiro) | 균형적 AZ 배치 |
| **ElastiCache** | RouteByLatency + PREFER_REPLICA_AZ (Kiro) | 최소 코드 변경 |
| **DocumentDB** | 개별 instance EP (Kiro) | Custom EP 미지원 대응 |
| **K8s overlay** | common/ + az-a/az-c (Codex) | DRY 원칙 |
| **앱 코드** | Kiro 코드 + Codex 환경변수 | 상세 + 명시적 |

---

## AI별 평가 요약

| 평가 축 | Claude | Codex | Gemini | Kiro-CLI |
|---------|--------|-------|--------|----------|
| **구조 설계** | ★★★★ | ★★★★★ | ★★★ | ★★★★ |
| **코드 상세도** | ★★★ | ★★★★ | ★★ | ★★★★★ |
| **비용 분석** | ★★ | ★★★★★ | ★★★★ | ★★ |
| **AWS 제약 인지** | ★★★★ | ★★★★ | ★★★ | ★★★★★ |
| **실행 가능성** | ★★★★ | ★★★ | ★★★★ | ★★★★★ |
| **기존 패턴 일관성** | ★★★★★ | ★★★ | ★★ | ★★★★ |
| **종합** | **4.0** | **3.8** | **3.0** | **4.2** |

### 핵심 차별점
- **Codex**: 가장 세밀한 비용/구조 분석. 5-layer TF와 KAFKA_BROKERS_LOCAL/FALLBACK 패턴이 독창적. 단 오버엔지니어링 경향.
- **Gemini**: 간결한 설계와 직관적 비용 비교. 단 코드 상세도 부족, DocumentDB Custom EP 미지원 인지 실패.
- **Kiro-CLI**: 코드베이스를 실제로 읽고 가장 구체적인 코드 변경 제시. DocumentDB 제약 유일하게 인지. RackAffinityGroupBalancer 발견.
- **Claude**: 기존 코드베이스와의 일관성 최우선. 보수적이지만 안정적. MSK Go rack-aware 포기가 약점.

---

## Implementation Roadmap

```
Phase 1: Infrastructure (Week 1)
  └── TF shared/ (VPC, SG, KMS, Data Stores)
  └── TF eks-az-a/ + eks-az-c/

Phase 2: K8s Manifests (Week 2)
  └── overlays/ap-northeast-2/{common,az-a,az-c}/
  └── Karpenter EC2NodeClass + NodePool per AZ
  └── ArgoCD ApplicationSet update

Phase 3: App Code (Week 2-3)
  └── DB_WRITE_HOST / DB_READ_HOST_LOCAL support
  └── ElastiCache RouteByLatency
  └── Kafka CLIENT_RACK + KAFKA_BROKERS_LOCAL

Phase 4: Verification (Week 3)
  └── terraform plan (all 3 layers)
  └── kubectl kustomize build
  └── Cross-AZ traffic monitoring
```

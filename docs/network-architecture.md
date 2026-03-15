# Network Architecture

## Multi-Region Network Topology

```
                              ┌──────────────┐
                              │   Internet    │
                              └──────┬───────┘
                                     │
                              ┌──────┴───────┐
                              │  Route 53     │  mall.atomai.click
                              │  (DNS CNAME)  │  → CloudFront Distribution
                              └──────┬───────┘
                                     │
                              ┌──────┴───────┐
                              │  CloudFront   │  CDN (400+ Edge Locations)
                              │  + WAF v2     │  DDoS Protection, Rate Limiting
                              └──────┬───────┘
                                     │
                              ┌──────┴───────┐
                              │  Route 53     │  Origin: api.atomai.click
                              │  (Latency)    │  Latency-based Routing
                              │  Health Check │  Automatic Failover
                              └──┬────────┬──┘
                                 │        │
              ┌──────────────────┘        └──────────────────┐
              ▼                                              ▼
   ┌──────────────────────┐                     ┌──────────────────────┐
   │    us-east-1 VPC     │                     │    us-west-2 VPC     │
   │   10.0.0.0/16        │                     │   10.1.0.0/16        │
   │                      │   Transit Gateway   │                      │
   │  ┌────────────────┐  │      Peering        │  ┌────────────────┐  │
   │  │ Public Subnets │  │◄────────────────────►│  │ Public Subnets │  │
   │  │ (ALB, NAT GW)  │  │                     │  │ (ALB, NAT GW)  │  │
   │  └────────────────┘  │                     │  └────────────────┘  │
   │  ┌────────────────┐  │                     │  ┌────────────────┐  │
   │  │ Private Subnets│  │                     │  │ Private Subnets│  │
   │  │ (EKS Nodes)    │  │                     │  │ (EKS Nodes)    │  │
   │  └────────────────┘  │                     │  └────────────────┘  │
   │  ┌────────────────┐  │                     │  ┌────────────────┐  │
   │  │ Data Subnets   │  │                     │  │ Data Subnets   │  │
   │  │ (Aurora, DocDB, │  │                     │  │ (Aurora, DocDB, │  │
   │  │  ElastiCache,  │  │                     │  │  ElastiCache,  │  │
   │  │  MSK, OS)      │  │                     │  │  MSK, OS)      │  │
   │  └────────────────┘  │                     │  └────────────────┘  │
   └──────────────────────┘                     └──────────────────────┘
```

---

## 1. VPC Design

### CIDR Allocation

| Region | VPC CIDR | Public Subnets | Private Subnets | Data Subnets |
|--------|----------|----------------|-----------------|--------------|
| us-east-1 | 10.0.0.0/16 | 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 | 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24 | 10.0.21.0/24, 10.0.22.0/24, 10.0.23.0/24 |
| us-west-2 | 10.1.0.0/16 | 10.1.1.0/24, 10.1.2.0/24, 10.1.3.0/24 | 10.1.11.0/24, 10.1.12.0/24, 10.1.13.0/24 | 10.1.21.0/24, 10.1.22.0/24, 10.1.23.0/24 |

### Subnet Architecture (3-Tier, 3-AZ)

```
┌─────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/16)                │
│                                                     │
│  AZ-a              AZ-b              AZ-c           │
│  ┌─────────┐      ┌─────────┐      ┌─────────┐    │
│  │ Public  │      │ Public  │      │ Public  │    │  ← ALB, NAT Gateway
│  │ 10.0.1  │      │ 10.0.2  │      │ 10.0.3  │    │
│  ├─────────┤      ├─────────┤      ├─────────┤    │
│  │ Private │      │ Private │      │ Private │    │  ← EKS Worker Nodes
│  │ 10.0.11 │      │ 10.0.12 │      │ 10.0.13 │    │
│  ├─────────┤      ├─────────┤      ├─────────┤    │
│  │  Data   │      │  Data   │      │  Data   │    │  ← Aurora, DocDB, ElastiCache, MSK, OpenSearch
│  │ 10.0.21 │      │ 10.0.22 │      │ 10.0.23 │    │
│  └─────────┘      └─────────┘      └─────────┘    │
└─────────────────────────────────────────────────────┘
```

---

## 2. Transit Gateway Peering

리전 간 통신은 Transit Gateway Peering을 통해 이루어집니다.

```
┌──────────────┐                              ┌──────────────┐
│  us-east-1   │                              │  us-west-2   │
│  TGW         │◄────── TGW Peering ────────►│  TGW         │
│              │     (encrypted, AWS backbone) │              │
│  ┌────────┐  │                              │  ┌────────┐  │
│  │  VPC   │──┤                              ├──│  VPC   │  │
│  └────────┘  │                              │  └────────┘  │
└──────────────┘                              └──────────────┘

Route: 10.1.0.0/16 → TGW Peering Attachment (us-east-1 → us-west-2)
Route: 10.0.0.0/16 → TGW Peering Attachment (us-west-2 → us-east-1)
```

### Use Cases
- Aurora Global Write Forwarding (us-west-2 → us-east-1)
- Cross-region service-to-service calls (emergency fallback)
- MSK Replicator traffic

---

## 3. Security Groups

### Inbound Rules

| Security Group | Source | Port | Purpose |
|----------------|--------|------|---------|
| ALB | 0.0.0.0/0 | 443 | HTTPS from CloudFront |
| EKS Nodes | ALB SG | 30000-32767 | NodePort range |
| EKS Nodes | EKS Nodes SG | All | Pod-to-Pod |
| Aurora | EKS Nodes SG | 5432 | PostgreSQL |
| DocumentDB | EKS Nodes SG | 27017 | MongoDB protocol |
| ElastiCache | EKS Nodes SG | 6379 | Valkey/Redis |
| MSK | EKS Nodes SG | 9092-9096 | Kafka (plaintext + SASL) |
| OpenSearch | EKS Nodes SG | 443 | HTTPS (VPC endpoint) |

### Principle: Least Privilege
- 모든 Security Group은 VPC CIDR 내에서만 통신 허용
- Data Subnet의 리소스는 인터넷 직접 접근 불가
- NAT Gateway를 통한 아웃바운드만 허용 (패키지 업데이트 등)

---

## 4. Edge Network

### CloudFront Distribution

```
                    ┌────────────────────────────┐
                    │      CloudFront             │
                    │                            │
                    │  Behaviors:                 │
                    │  /api/*  → ALB Origin       │
                    │  /static/* → S3 Origin      │
                    │  /*     → ALB Origin        │
                    │                            │
                    │  Cache Policy:              │
                    │  - Static: 24h             │
                    │  - API: No cache (pass)    │
                    │                            │
                    │  ALB Origin:               │
                    │  api.atomai.click           │
                    │  (Route 53 Latency Record) │
                    │  → nearest region ALB      │
                    └────────────────────────────┘
```

### Traffic Flow (상세)

```
[User] → DNS: mall.atomai.click
       → Route 53 CNAME → d1muyxliujbszf.cloudfront.net
       → CloudFront Edge (nearest POP)
           ├─ Cache HIT → 즉시 응답
           └─ Cache MISS → Origin: api.atomai.click
                          → Route 53 Latency Routing
                          → nearest ALB (us-east-1 or us-west-2)
                          → EKS Service → Pod
```

### WAF v2 Rules

| Rule | Action | Description |
|------|--------|-------------|
| AWS-AWSManagedRulesCommonRuleSet | Block | OWASP Top 10 방어 |
| AWS-AWSManagedRulesSQLiRuleSet | Block | SQL Injection 방어 |
| AWS-AWSManagedRulesKnownBadInputsRuleSet | Block | 알려진 악성 입력 차단 |
| RateLimit | Block (2000/5min) | 과도한 요청 제한 |
| GeoRestriction | Allow (KR, US, JP) | 허용 국가 제한 |

### Route 53

**Frontend DNS (CloudFront 앞단)**

| Record | Type | Routing | Target |
|--------|------|---------|--------|
| mall.atomai.click | CNAME | Simple | d1muyxliujbszf.cloudfront.net |

**Origin DNS (CloudFront → ALB, Latency-based)**

| Record | Type | Routing | Target |
|--------|------|---------|--------|
| api.atomai.click | A | Latency (us-east-1) | us-east-1 ALB |
| api.atomai.click | A | Latency (us-west-2) | us-west-2 ALB |

CloudFront Origin이 `api.atomai.click`을 가리키면, Route 53 Latency Routing이 CloudFront edge에서 가장 가까운 리전의 ALB로 자동 라우팅합니다.

Health Check: HTTP 200 from ALB /health endpoint, 30s interval, 3 failure threshold

---

## 5. VPC Endpoints

비용 최적화 및 보안을 위해 주요 AWS 서비스에 VPC Endpoint 사용:

| Service | Endpoint Type | Purpose |
|---------|--------------|---------|
| S3 | Gateway | S3 접근 (NAT GW 비용 절감) |
| ECR (api/dkr) | Interface | 컨테이너 이미지 Pull |
| STS | Interface | IRSA 토큰 교환 |
| CloudWatch Logs | Interface | 로그 전송 |
| Secrets Manager | Interface | 시크릿 접근 |

---

## 6. EKS Networking

### Pod Networking (VPC-CNI)

```
┌─────────────────────────────────────────┐
│            EKS Worker Node              │
│  Primary ENI: 10.0.11.10               │
│  Secondary ENI: 10.0.11.20             │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │  Pod A   │  │  Pod B   │            │
│  │ 10.0.11.15│  │10.0.11.16│            │
│  └──────────┘  └──────────┘            │
│                                         │
│  Pods get IPs from VPC subnet CIDR     │
│  → Direct VPC routing, no overlay      │
└─────────────────────────────────────────┘
```

- **CNI Plugin**: Amazon VPC CNI (aws-node)
- **IP Management**: Pod에 VPC Subnet IP 직접 할당
- **장점**: 네이티브 VPC 라우팅으로 오버레이 오버헤드 없음
- **Prefix Delegation**: 노드당 더 많은 Pod IP 할당 가능

### Service Mesh (Future)

현재는 Kubernetes Service + Ingress로 서비스 간 통신을 처리합니다.
향후 필요시 Istio 또는 AWS App Mesh 도입 가능합니다.

---

## 7. DNS Resolution

### Internal DNS (CoreDNS)

```
service-name.namespace.svc.cluster.local → ClusterIP
```

### External DNS (Route 53)

```
mall.atomai.click → CloudFront → api.atomai.click (Latency) → ALB → EKS Service → Pod
```

### Database DNS

Aurora, DocumentDB, ElastiCache는 AWS 관리형 DNS 엔드포인트 사용:
```
production-aurora-global-us-east-1.cluster-xxx.us-east-1.rds.amazonaws.com
production-docdb-global-us-east-1.cluster-xxx.us-east-1.docdb.amazonaws.com
clustercfg.production-elasticache-us-east-1.xxx.use1.cache.amazonaws.com
```

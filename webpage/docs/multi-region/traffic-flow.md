---
sidebar_position: 2
title: Traffic Flow
description: End-to-end 트래픽 흐름 — CloudFront → Route53 → NLB → EKS
---

# Traffic Flow

## End-to-End Path

```
User → mall.atomai.click
     → CloudFront (+ WAF)
     → api-internal.atomai.click (Route53 Latency-based → nearest NLB)
     → NLB (SG: CloudFront prefix list only, TLS:443)
     → API Gateway pods (EKS)
     → Internal services (20 microservices)
```

## Traffic Routing Detail

### 1. CloudFront (Edge)

- 모든 퍼블릭 트래픽의 진입점
- Frontend static assets는 S3에서 OAC로 서빙
- API 요청(`/api/*`)은 `api-internal.atomai.click`으로 라우팅
- WAF 현재 비활성화 (Bot Control이 curl/headless 브라우저 차단하여 임시 해제)

### 2. Route53 (DNS)

- `api-internal.atomai.click` — **Latency-based routing**
- 사용자의 네트워크 위치에 따라 가장 가까운 리전의 NLB로 라우팅
- 각 리전에 별도의 A record (Alias to NLB)

### 3. NLB (Load Balancer)

- 리전별 Public subnet에 배포
- TLS termination at NLB (ACM certificate)
- Security Group: **CloudFront managed prefix list만 허용**
  - `com.amazonaws.global.cloudfront.origin-facing`
  - Port range: 80-443 (단일 규칙, prefix list 45엔트리 × 규칙 한도 60 제약)

### 4. API Gateway → Services

- API Gateway pod이 요청을 받아 내부 서비스로 라우팅
- 서비스 간 통신은 K8s Service DNS 사용
- Container port: 8080, K8s Service port: 80 → targetPort: 8080

## Write Forwarding

Secondary 리전(us-west-2)에서의 쓰기 요청은 Aurora Global Write Forwarding을 통해 Primary(us-east-1)로 전달됩니다.

```
us-west-2 Service → Aurora us-west-2 (Secondary)
                    → Write Forwarding → Aurora us-east-1 (Primary Writer)
                    → Replication → Aurora us-west-2 (eventually consistent)
```

:::warning 핵심 보안 규칙
모든 퍼블릭 트래픽은 **반드시** CloudFront를 경유합니다. NLB 보안 그룹은 CloudFront managed prefix list만 허용하며, `0.0.0.0/0` 인바운드 규칙은 **완전 금지**됩니다.

- us-east-1 ALB SG: `sg-0123456789abcdef0`
- us-west-2 ALB SG: `sg-0abcdef1234567890`
:::

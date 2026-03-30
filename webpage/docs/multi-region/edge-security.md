---
sidebar_position: 6
title: Edge & Security
description: CloudFront, WAF, Route53, Security Groups, Cognito, IRSA, KMS
---

# Edge & Security

## CloudFront Distributions

| Distribution | Domain | Origin |
|-------------|--------|--------|
| **Main (Frontend)** | `mall.atomai.click` | S3 (Static Assets) + API (`api-internal.*`) |
| **ArgoCD** | `argocd.atomai.click` | NLB (ArgoCD server) |
| **Grafana** | `grafana.atomai.click` | NLB (Grafana server) |

**WAF**: 현재 비활성화 — Bot Control이 curl/headless 브라우저를 차단하여 임시 해제. ArgoCD/Grafana는 자체 인증으로 보호.

## Route53 Records

| Record | Type | Routing Policy | Target |
|--------|------|---------------|--------|
| `api-internal.atomai.click` | A (Alias) | **Latency-based** | 리전별 NLB |
| `mall.atomai.click` | A (Alias) | Simple | CloudFront |
| `argocd.atomai.click` | A (Alias) | Simple | CloudFront (ArgoCD) |
| `grafana.atomai.click` | A (Alias) | Simple | CloudFront (Grafana) |
| `argocd-internal.atomai.click` | A (Alias) | Latency-based | 리전별 NLB |

## Security Groups Strategy

:::danger Zero Public Exposure
모든 보안 그룹은 Terraform으로 관리됩니다. K8s ALB Controller가 자동 생성하는 SG를 방지하기 위해 `manage-backend-security-group-rules: "false"`를 **필수** 설정합니다.
:::

| SG | us-east-1 | us-west-2 | Inbound Source |
|----|-----------|-----------|----------------|
| **ALB SG** | `sg-0123456789abcdef0` | `sg-0abcdef1234567890` | CloudFront Prefix List (80-443) |
| **NLB SG** | TF managed | TF managed | CloudFront Prefix List |
| **EKS SG** | TF managed | TF managed | VPC CIDR only |
| **Data SGs** | TF managed | TF managed | EKS Node SG only |

### K8s Ingress 필수 어노테이션

```yaml
# ALB Ingress
alb.ingress.kubernetes.io/security-groups: sg-0123456789abcdef0
alb.ingress.kubernetes.io/manage-backend-security-group-rules: "false"

# Service type: LoadBalancer
service.beta.kubernetes.io/aws-load-balancer-security-groups: sg-0123456789abcdef0
```

## Amazon Cognito

> **Status: In Progress**

Cognito User Pool을 통한 이메일 기반 인증.

- **Terraform Module**: `terraform/modules/security/cognito/`
- **Go Middleware**: `src/shared/go/pkg/auth/` — Gin 미들웨어로 JWT 검증
  - JWKS 캐싱
  - `COGNITO_USER_POOL_ID` 미설정 시 graceful degradation

## IAM / IRSA

| IRSA Role | 서비스 | 권한 |
|-----------|--------|------|
| `production-otel-collector-*` | OTel Collector | X-Ray PutTraceSegments, CloudWatch Logs |
| `production-dsql-access-*` | Go Services | DSQL token generation |
| `production-tempo-*` | Tempo | S3 read/write |
| EBS CSI IRSA | EBS CSI Driver | EBS volume management |
| EFS CSI IRSA | EFS CSI Driver | EFS access point management |
| ALB Controller IRSA | ALB Controller | EC2, ELB, WAF management |

## KMS Encryption

리전별 서비스 전용 KMS CMK(Customer Managed Key):

| Key Alias | 용도 |
|-----------|------|
| `aurora` | Aurora/DocumentDB 클러스터 암호화 |
| `elasticache` | ElastiCache at-rest 암호화 |
| `msk` | MSK 브로커 디스크 암호화 |
| `s3` | S3 버킷 SSE-KMS + CloudFront OAC Decrypt |
| `documentdb` | DocumentDB 클러스터 암호화 |

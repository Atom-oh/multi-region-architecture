---
title: 보안
sidebar_position: 7
---

# 보안

Multi-Region Shopping Mall은 다층 보안 아키텍처를 구현하여 인프라, 데이터, 애플리케이션 수준에서 포괄적인 보안을 제공합니다. 이 문서에서는 WAF, 암호화, IAM, 네트워크 보안에 대해 상세히 설명합니다.

## 보안 아키텍처 개요

```mermaid
flowchart TB
    subgraph Edge["Edge Security"]
        CF[CloudFront]
        WAF[AWS WAF v2]
        Shield[AWS Shield]
    end

    subgraph Network["Network Security"]
        VPC[VPC]
        SG[Security Groups]
        NACL[Network ACLs]
        TGW[Transit Gateway]
    end

    subgraph Identity["Identity & Access"]
        IAM[IAM]
        IRSA[IRSA]
        SM[Secrets Manager]
    end

    subgraph Data["Data Security"]
        KMS[AWS KMS]
        TLS[TLS/SSL]
        Encryption[At-Rest Encryption]
    end

    subgraph Application["Application Security"]
        Auth[Authentication]
        AuthZ[Authorization]
        Validation[Input Validation]
    end

    Edge --> Network --> Identity --> Data --> Application
```

## AWS WAF v2

### WAF 아키텍처

```mermaid
flowchart LR
    Internet((Internet)) --> CF[CloudFront]
    CF --> WAF[AWS WAF v2]
    WAF --> ALB[ALB]
    ALB --> EKS[EKS]

    subgraph Rules["WAF Rules"]
        R1[AWS Managed Rules]
        R2[Rate Limiting]
        R3[Geo Restriction]
        R4[Custom Rules]
    end

    WAF --> Rules
```

### WAF 규칙 구성

#### 1. AWS Managed Rules

| 규칙 세트 | 우선순위 | 액션 | 설명 |
|-----------|----------|------|------|
| **AWSManagedRulesCommonRuleSet** | 1 | Block | 일반적인 웹 취약점 차단 |
| **AWSManagedRulesSQLiRuleSet** | 2 | Block | SQL Injection 공격 차단 |
| **AWSManagedRulesKnownBadInputsRuleSet** | 3 | Block | 알려진 악성 입력 차단 |
| **AWSManagedRulesLinuxRuleSet** | 4 | Block | Linux 특화 공격 차단 |
| **AWSManagedRulesAmazonIpReputationList** | 5 | Block | 악성 IP 차단 |

#### 2. Rate Limiting

```hcl
resource "aws_wafv2_web_acl" "main" {
  name        = "production-waf"
  description = "Production WAF Web ACL"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate Limiting: 5분에 2000 요청
  rule {
    name     = "RateLimitRule"
    priority = 10

    override_action {
      none {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    action {
      block {}
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # API 엔드포인트별 세분화된 Rate Limit
  rule {
    name     = "LoginRateLimit"
    priority = 11

    statement {
      rate_based_statement {
        limit              = 100  # 5분에 100회
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = "/api/auth/login"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    action {
      block {
        custom_response {
          response_code = 429
          custom_response_body_key = "TooManyRequests"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "LoginRateLimit"
      sampled_requests_enabled   = true
    }
  }
}
```

#### 3. Geo Restriction

```hcl
# 허용 국가: 한국(KR), 미국(US), 일본(JP)
rule {
  name     = "GeoRestriction"
  priority = 20

  statement {
    not_statement {
      statement {
        geo_match_statement {
          country_codes = ["KR", "US", "JP"]
        }
      }
    }
  }

  action {
    block {
      custom_response {
        response_code = 403
        custom_response_body_key = "GeoBlocked"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "GeoRestriction"
    sampled_requests_enabled   = true
  }
}
```

### WAF 규칙 요약 테이블

| 규칙 | 우선순위 | Rate Limit | 액션 | 적용 대상 |
|------|----------|------------|------|-----------|
| AWS Common Rules | 1 | - | Block | 모든 요청 |
| SQLi Rules | 2 | - | Block | 모든 요청 |
| Known Bad Inputs | 3 | - | Block | 모든 요청 |
| IP Reputation | 5 | - | Block | 모든 요청 |
| Global Rate Limit | 10 | 2000/5min | Block | 모든 요청 |
| Login Rate Limit | 11 | 100/5min | Block | /api/auth/login |
| Order Rate Limit | 12 | 50/5min | Block | /api/orders POST |
| Geo Restriction | 20 | - | Block | 비허용 국가 |

## KMS 암호화

### 암호화 아키텍처

```mermaid
flowchart TB
    subgraph KMS["AWS KMS"]
        CMK[Customer Managed Keys]
        DEK[Data Encryption Keys]
    end

    subgraph Data["암호화된 데이터"]
        Aurora[(Aurora PostgreSQL)]
        DocDB[(DocumentDB)]
        Cache[(ElastiCache)]
        S3[(S3 Buckets)]
        EBS[(EBS Volumes)]
        MSK[MSK Kafka]
    end

    CMK --> DEK
    DEK --> Aurora & DocDB & Cache & S3 & EBS & MSK
```

### 데이터 스토어별 암호화

| 데이터 스토어 | 암호화 유형 | KMS 키 | 알고리즘 |
|--------------|-------------|--------|----------|
| **Aurora PostgreSQL** | At-Rest | Customer Managed | AES-256 |
| **DocumentDB** | At-Rest | Customer Managed | AES-256 |
| **ElastiCache Valkey** | At-Rest + In-Transit | Customer Managed | AES-256, TLS 1.2 |
| **S3** | At-Rest | Customer Managed | AES-256 (SSE-KMS) |
| **EBS** | At-Rest | Customer Managed | AES-256 |
| **MSK Kafka** | At-Rest + In-Transit | Customer Managed | AES-256, TLS 1.2 |
| **OpenSearch** | At-Rest + In-Transit | Customer Managed | AES-256, TLS 1.2 |
| **Secrets Manager** | At-Rest | AWS Managed | AES-256 |

### KMS Key Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow RDS to use the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "123456789012"
        }
      }
    },
    {
      "Sid": "Allow EKS Pods via IRSA",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/eks-*-irsa"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*"
    }
  ]
}
```

### Terraform 구성

```hcl
# KMS Key for Data Encryption
resource "aws_kms_key" "data_encryption" {
  description             = "KMS key for data encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow services to use the key"
        Effect = "Allow"
        Principal = {
          Service = [
            "rds.amazonaws.com",
            "elasticache.amazonaws.com",
            "kafka.amazonaws.com",
            "es.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "production-data-encryption-key"
    Environment = "production"
  }
}

resource "aws_kms_alias" "data_encryption" {
  name          = "alias/production-data-encryption"
  target_key_id = aws_kms_key.data_encryption.key_id
}
```

## Secrets Manager

### 시크릿 관리 구조

```mermaid
flowchart TB
    subgraph Secrets["Secrets Manager"]
        DB_Creds[Database Credentials]
        API_Keys[API Keys]
        Kafka_Creds[Kafka SASL Credentials]
        TLS_Certs[TLS Certificates]
    end

    subgraph Consumers["시크릿 사용자"]
        EKS[EKS Pods]
        Lambda[Lambda Functions]
        CICD[CI/CD Pipeline]
    end

    subgraph Rotation["자동 로테이션"]
        Rotator[Rotation Lambda]
    end

    DB_Creds & API_Keys & Kafka_Creds --> EKS
    DB_Creds --> Lambda
    API_Keys --> CICD
    Rotator -->|"30일마다"| DB_Creds
```

### 시크릿 목록

| 시크릿 이름 | 유형 | 로테이션 주기 | 사용 서비스 |
|-------------|------|--------------|-------------|
| `production/aurora/master` | DB Credentials | 30일 | Order, Payment, Inventory |
| `production/documentdb/master` | DB Credentials | 30일 | Product, Profile, Review |
| `production/msk/sasl` | SASL Credentials | 90일 | All Kafka consumers |
| `production/opensearch/master` | Service Credentials | 30일 | Search, Analytics |
| `production/api/jwt-secret` | API Secret | 90일 | API Gateway |

### 시크릿 접근 예시

```python
# Python - Secrets Manager 사용
import boto3
import json
from botocore.exceptions import ClientError

def get_db_credentials(secret_name: str) -> dict:
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name='us-east-1'
    )

    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return {
            'host': secret['host'],
            'port': secret['port'],
            'username': secret['username'],
            'password': secret['password'],
            'database': secret['dbname']
        }
    except ClientError as e:
        raise e

# 사용 예시
creds = get_db_credentials('production/aurora/master')
connection_string = f"postgresql://{creds['username']}:{creds['password']}@{creds['host']}:{creds['port']}/{creds['database']}"
```

## IAM & IRSA

### IRSA (IAM Roles for Service Accounts)

```mermaid
flowchart TB
    subgraph EKS["EKS Cluster"]
        SA[Service Account]
        Pod[Application Pod]
    end

    subgraph IAM["IAM"]
        Role[IAM Role]
        Policy[IAM Policy]
    end

    subgraph AWS["AWS Services"]
        S3[(S3)]
        SM[(Secrets Manager)]
        KMS[(KMS)]
        SQS[(SQS)]
    end

    SA -->|"annotated with"| Role
    Role --> Policy
    Pod -->|"assumes"| Role
    Role -->|"allows"| S3 & SM & KMS & SQS
```

### 서비스별 IAM Role

| 서비스 | IAM Role | 권한 |
|--------|----------|------|
| **Order Service** | `order-service-irsa` | SecretsManager:GetSecretValue, KMS:Decrypt, SQS:* |
| **Payment Service** | `payment-service-irsa` | SecretsManager:GetSecretValue, KMS:Decrypt |
| **Product Catalog** | `product-catalog-irsa` | SecretsManager:GetSecretValue, S3:GetObject |
| **Search Service** | `search-service-irsa` | SecretsManager:GetSecretValue, ES:* |
| **Notification** | `notification-irsa` | SecretsManager:GetSecretValue, SES:SendEmail, SNS:Publish |
| **Analytics** | `analytics-irsa` | SecretsManager:GetSecretValue, S3:*, Athena:* |

### IRSA 구성

```hcl
# IRSA for Order Service
module "order_service_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "order-service-irsa"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["production:order-service"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.order_service.arn
  }
}

resource "aws_iam_policy" "order_service" {
  name        = "order-service-policy"
  description = "Policy for Order Service"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:production/aurora/*",
          "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:production/msk/*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.data_encryption.arn
      }
    ]
  })
}
```

### Kubernetes Service Account

```yaml
# order-service ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-service
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/order-service-irsa
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: production
spec:
  template:
    spec:
      serviceAccountName: order-service
      containers:
      - name: order-service
        image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/order-service:latest
        env:
        - name: AWS_REGION
          value: us-east-1
```

## 네트워크 보안

### Security Groups

```mermaid
flowchart TB
    Internet((Internet))
    Internet -->|443| ALB_SG

    subgraph VPC["VPC Security"]
        ALB_SG[ALB Security Group<br/>Inbound: 443 from 0.0.0.0/0]
        EKS_SG[EKS Security Group<br/>Inbound: 8080 from ALB_SG]
        Data_SG[Data Security Groups<br/>Inbound: from EKS_SG only]
    end

    ALB_SG -->|8080| EKS_SG
    EKS_SG -->|5432,27017,6379,9096| Data_SG
```

### Network ACLs

| NACL | 인바운드 규칙 | 아웃바운드 규칙 | 적용 서브넷 |
|------|--------------|----------------|-------------|
| **Public** | 443, 80 from 0.0.0.0/0 | All to 0.0.0.0/0 | Public Subnets |
| **Private** | All from VPC CIDR | All to 0.0.0.0/0 | Private Subnets |
| **Data** | All from Private CIDR | All to Private CIDR | Data Subnets |

### 데이터 서브넷 NACL

```hcl
resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.data[*].id

  # 인바운드: Private 서브넷에서만 접근 허용
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.11.0/24"  # Private Subnet A
    from_port  = 0
    to_port    = 65535
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 101
    action     = "allow"
    cidr_block = "10.0.12.0/24"  # Private Subnet B
    from_port  = 0
    to_port    = 65535
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 102
    action     = "allow"
    cidr_block = "10.0.13.0/24"  # Private Subnet C
    from_port  = 0
    to_port    = 65535
  }

  # Cross-region replication
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "10.1.0.0/16"  # us-west-2 VPC
    from_port  = 0
    to_port    = 65535
  }

  # 아웃바운드: Private 서브넷으로만 응답
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 65535
  }

  tags = {
    Name = "data-subnet-nacl"
  }
}
```

## TLS/SSL

### TLS 구성

| 구간 | TLS 버전 | 인증서 | 관리 |
|------|----------|--------|------|
| CloudFront ↔ Client | TLS 1.2+ | ACM (*.atomai.click) | AWS Managed |
| ALB ↔ CloudFront | TLS 1.2+ | ACM | AWS Managed |
| EKS ↔ ALB | TLS 1.2 | Self-signed | Kubernetes |
| Services ↔ Aurora | TLS 1.2 | RDS CA | AWS Managed |
| Services ↔ DocumentDB | TLS 1.2 | RDS CA | AWS Managed |
| Services ↔ ElastiCache | TLS 1.2 | ElastiCache CA | AWS Managed |
| Services ↔ MSK | TLS 1.2 | MSK CA | AWS Managed |

### 애플리케이션 TLS 설정

```go
// Go - TLS 설정 예시
package main

import (
    "crypto/tls"
    "crypto/x509"
    "database/sql"
    "io/ioutil"

    _ "github.com/lib/pq"
)

func connectToAurora() (*sql.DB, error) {
    // RDS CA 인증서 로드
    rootCert, err := ioutil.ReadFile("/etc/ssl/certs/rds-ca-2019-root.pem")
    if err != nil {
        return nil, err
    }

    rootCertPool := x509.NewCertPool()
    rootCertPool.AppendCertsFromPEM(rootCert)

    tlsConfig := &tls.Config{
        RootCAs:    rootCertPool,
        MinVersion: tls.VersionTLS12,
    }

    connStr := fmt.Sprintf(
        "host=%s port=5432 user=%s password=%s dbname=%s sslmode=verify-full sslrootcert=/etc/ssl/certs/rds-ca-2019-root.pem",
        host, user, password, dbname,
    )

    return sql.Open("postgres", connStr)
}
```

## 보안 모니터링

### CloudTrail 로깅

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "production-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail.arn

  kms_key_id = aws_kms_key.cloudtrail.arn

  tags = {
    Name = "production-cloudtrail"
  }
}
```

### GuardDuty 활성화

```hcl
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "production-guardduty"
  }
}
```

### 보안 알림

```hcl
# WAF 블록 알림
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  alarm_name          = "waf-high-block-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000

  dimensions = {
    WebACL = aws_wafv2_web_acl.main.name
    Region = "us-east-1"
    Rule   = "ALL"
  }

  alarm_actions = [aws_sns_topic.security_alerts.arn]

  alarm_description = "High number of WAF blocked requests"
}

# GuardDuty 위협 탐지 알림
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-findings"
  description = "GuardDuty finding events"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}
```

## 보안 체크리스트

### 인프라 보안

- [x] VPC 3-tier 아키텍처 (Public/Private/Data)
- [x] Security Groups - 최소 권한 원칙
- [x] Network ACLs - 서브넷 레벨 필터링
- [x] VPC Flow Logs 활성화
- [x] VPC Endpoints - Private 연결

### 데이터 보안

- [x] KMS Customer Managed Keys 사용
- [x] 모든 데이터 스토어 At-Rest 암호화
- [x] TLS 1.2+ In-Transit 암호화
- [x] Secrets Manager 자동 로테이션

### 접근 제어

- [x] IAM IRSA - Pod 레벨 권한
- [x] 최소 권한 원칙 적용
- [x] MFA 활성화 (콘솔 접근)
- [x] CloudTrail 감사 로깅

### 애플리케이션 보안

- [x] WAF v2 - OWASP Top 10 방어
- [x] Rate Limiting 적용
- [x] Geo Restriction (KR/US/JP)
- [x] 입력 검증 및 새니타이징

### 모니터링

- [x] GuardDuty 위협 탐지
- [x] CloudWatch 알람
- [x] Security Hub 통합
- [x] 실시간 알림 구성

## 다음 단계

- [네트워크 아키텍처](./network) - 네트워크 보안 상세
- [재해 복구](./disaster-recovery) - DR 보안 고려사항

---
sidebar_position: 1
title: Overview
description: Multi-Region 아키텍처 개요 — us-east-1 (Primary) + us-west-2 (Secondary)
---

# Multi-Region Architecture Overview

AWS 기반 멀티리전 쇼핑몰 플랫폼 — **Write-Primary / Read-Local** 패턴

:::info Executive Summary
본 아키텍처는 AWS의 두 리전(**us-east-1** Primary, **us-west-2** Secondary)에 걸쳐 운영되는 쇼핑몰 플랫폼입니다. **Write-Primary / Read-Local** 패턴을 채택하여 쓰기는 Primary 리전으로 포워딩하고, 읽기는 가장 가까운 리전에서 처리합니다.

20개 마이크로서비스가 5개 도메인(Core, User, Fulfillment, Business, Platform)으로 조직되며, Go/Gin, Java/Spring Boot, Python/FastAPI 세 가지 기술 스택으로 구현됩니다.
:::

## Key Metrics

| Metric | Value |
|--------|-------|
| **Active Regions** | 2 (us-east-1, us-west-2) |
| **Microservices** | 20 |
| **Terraform Resources** | ~520 (260 per region) |
| **Service Domains** | 5 |
| **Data Stores** | 7 types |
| **EKS Nodes** | ~30 total (~15 per region) |

## Platform Info

| 항목 | 값 |
|------|-----|
| **AWS Account** | 123456789012 |
| **Domain** | atomai.click (wildcard cert `*.atomai.click`) |
| **EKS Cluster** | `multi-region-mall` (both regions) |
| **EKS Version** | v1.35 (v1.35.2-eks-f69f56f) |
| **Terraform** | ≥ 1.9, AWS Provider ≥ 6.0 |
| **State Backend** | S3 `multi-region-mall-terraform-state` + DynamoDB lock |

## Design Principles

### Write-Primary / Read-Local

모든 쓰기 요청은 us-east-1(Primary)에서 처리. 읽기는 각 리전의 로컬 복제본 사용. Aurora Global Write Forwarding으로 Secondary에서도 쓰기 가능 (forwarded).

### CloudFront-First Security

모든 퍼블릭 트래픽은 반드시 CloudFront를 통과. ALB/NLB 보안 그룹은 CloudFront managed prefix list로만 제한. `0.0.0.0/0` 인바운드 규칙 **완전 금지**.

### GitOps with ArgoCD

모든 K8s 리소스는 ArgoCD ApplicationSet으로 관리. 리전별 Kustomize overlay로 환경 분리. Git 커밋이 배포의 single source of truth.

### Unified Observability

OTel Collector가 traces/logs/metrics를 통합 수집. ClickHouse + Tempo + Prometheus 3중 백엔드. Grafana에서 metric → trace → log 연결 (exemplar).

---
id: intro
title: Multi-Region Shopping Mall
sidebar_position: 1
slug: /intro
---

# Multi-Region Shopping Mall

Technical documentation for an AWS-based multi-region microservices shopping mall platform.

## Project Overview

This project is a global-scale shopping mall platform modeled after Amazon.com's infrastructure patterns. It operates in an Active-Active configuration across two regions: **us-east-1** (Primary) and **us-west-2** (Secondary).

### Key Features

| Item | Details |
|------|---------|
| **Architecture Pattern** | Write-Primary / Read-Local |
| **Microservices** | 20 (Go 5, Java 7, Python 8) |
| **Data Stores** | Aurora PostgreSQL, DocumentDB, ElastiCache Valkey, OpenSearch, MSK Kafka |
| **Infrastructure** | Terraform 260+ resources, EKS, VPC 3-tier |
| **Deployment** | GitOps (ArgoCD), GitHub Actions CI/CD |
| **Observability** | OpenTelemetry, Grafana Tempo, Prometheus, X-Ray |
| **Availability Target** | 99.99% SLA, RPO <1s, RTO <10m |

### Service Domains

```mermaid
graph TB
    subgraph Core["Core (6)"]
        AG[API Gateway<br/>Go/Gin]
        PC[Product Catalog<br/>Python/FastAPI]
        SR[Search<br/>Go/Gin]
        CT[Cart<br/>Go/Gin]
        OD[Order<br/>Java/Spring]
        PM[Payment<br/>Java/Spring]
        IV[Inventory<br/>Go/Gin]
    end

    subgraph User["User (4)"]
        UA[User Account<br/>Java/Spring]
        UP[User Profile<br/>Python/FastAPI]
        WL[Wishlist<br/>Python/FastAPI]
        RV[Review<br/>Python/FastAPI]
    end

    subgraph Fulfillment["Fulfillment (3)"]
        SH[Shipping<br/>Python/FastAPI]
        WH[Warehouse<br/>Java/Spring]
        RT[Returns<br/>Java/Spring]
    end

    subgraph Business["Business (4)"]
        PR[Pricing<br/>Java/Spring]
        RC[Recommendation<br/>Python/FastAPI]
        NF[Notification<br/>Python/FastAPI]
        SL[Seller<br/>Java/Spring]
    end

    subgraph Platform["Platform (2)"]
        EB[Event Bus<br/>Go/Gin]
        AN[Analytics<br/>Python/FastAPI]
    end
```

### Infrastructure Stack

```mermaid
graph LR
    CF[CloudFront] --> R53[Route 53]
    R53 --> ALB1[ALB us-east-1]
    R53 --> ALB2[ALB us-west-2]
    ALB1 --> EKS1[EKS Cluster]
    ALB2 --> EKS2[EKS Cluster]
    EKS1 --> Aurora1[(Aurora Primary)]
    EKS1 --> DocDB1[(DocumentDB Primary)]
    EKS1 --> Cache1[(ElastiCache Primary)]
    EKS2 --> Aurora2[(Aurora Replica)]
    EKS2 --> DocDB2[(DocumentDB Replica)]
    EKS2 --> Cache2[(ElastiCache Replica)]
    Aurora1 -.->|replication| Aurora2
    DocDB1 -.->|replication| DocDB2
    Cache1 -.->|replication| Cache2
```

## Documentation Structure

- **[Getting Started](/getting-started/prerequisites)** - Prerequisites, Quick Start, Local Development Environment
- **[Architecture](/architecture/overview)** - System Design, Multi-Region, Network, Data
- **[Services](/services/overview)** - Detailed design documents for 20 microservices
- **[Infrastructure](/infrastructure/overview)** - Terraform, EKS, Databases, Edge
- **[Deployment](/deployment/overview)** - GitOps, CI/CD, Kustomize, Rollouts
- **[Observability](/observability/overview)** - Distributed Tracing, Metrics, Logging, Dashboards
- **[Operations](/operations/disaster-recovery)** - Disaster Recovery, Failover, Seed Data

## Technology Stack

| Category | Technology |
|----------|------------|
| **Languages** | Go 1.21, Java 17 (Spring Boot 3.2), Python 3.11 (FastAPI) |
| **Containers** | EKS (Kubernetes 1.29), Karpenter |
| **Databases** | Aurora PostgreSQL 15, DocumentDB 5.0, ElastiCache Valkey 7.2 |
| **Search** | OpenSearch 2.11 (nori Korean analyzer) |
| **Messaging** | MSK Kafka 3.5 (SASL/SCRAM) |
| **IaC** | Terraform 1.7+ |
| **GitOps** | ArgoCD, Kustomize |
| **Observability** | OpenTelemetry, Grafana Tempo, Prometheus, AWS X-Ray |
| **Edge** | CloudFront, WAF v2, Route 53 |
| **Security** | KMS, Secrets Manager, IAM (IRSA) |

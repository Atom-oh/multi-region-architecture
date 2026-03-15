---
sidebar_position: 1
title: Infrastructure Overview
description: Overview of the Terraform infrastructure architecture for the multi-region shopping mall platform
---

# Infrastructure Overview

The multi-region shopping mall platform uses **Terraform** to manage AWS infrastructure as code. It provisions **over 260 resources** across two regions: us-east-1 (primary) and us-west-2 (secondary).

## Architecture Diagram

```mermaid
flowchart TB
    subgraph "Terraform State Management"
        S3["S3 Bucket<br/>multi-region-mall-terraform-state"]
        DDB["DynamoDB<br/>State Locking"]
    end

    subgraph "Global Resources"
        R53["Route53<br/>Hosted Zone"]
        CF["CloudFront<br/>Distribution"]
        WAF["WAF v2<br/>Web ACL"]
    end

    subgraph "us-east-1 (Primary)"
        direction TB
        VPC1["VPC"]
        EKS1["EKS Cluster"]
        Aurora1["Aurora Global<br/>(Writer)"]
        DocDB1["DocumentDB<br/>(Primary)"]
        Cache1["ElastiCache<br/>(Primary)"]
        MSK1["MSK Kafka"]
        OS1["OpenSearch"]
    end

    subgraph "us-west-2 (Secondary)"
        direction TB
        VPC2["VPC"]
        EKS2["EKS Cluster"]
        Aurora2["Aurora Global<br/>(Reader)"]
        DocDB2["DocumentDB<br/>(Secondary)"]
        Cache2["ElastiCache<br/>(Secondary)"]
        MSK2["MSK Kafka"]
        OS2["OpenSearch"]
    end

    S3 --> DDB
    R53 --> CF
    CF --> WAF

    Aurora1 -.->|"Global Replication"| Aurora2
    DocDB1 -.->|"Global Replication"| DocDB2
    Cache1 -.->|"Global Datastore"| Cache2
    MSK1 -.->|"MSK Replicator"| MSK2
```

## State Management

Terraform state is centrally managed using S3 backend with DynamoDB locking.

| Component | Value |
|-----------|-------|
| S3 Bucket | `multi-region-mall-terraform-state` |
| DynamoDB Table | `terraform-state-lock` |
| Region | `us-east-1` |
| Encryption | AES-256 Server-Side Encryption |

```hcl
terraform {
  backend "s3" {
    bucket         = "multi-region-mall-terraform-state"
    key            = "environments/production/us-east-1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

## Module Dependency Diagram

```mermaid
flowchart TD
    subgraph "Layer 1: Foundation"
        VPC["VPC"]
        KMS["KMS"]
    end

    subgraph "Layer 2: Security"
        SG["Security Groups"]
        SM["Secrets Manager"]
        IAM["IAM"]
    end

    subgraph "Layer 3: Networking"
        TGW["Transit Gateway"]
        ALB["ALB"]
    end

    subgraph "Layer 4: Data"
        Aurora["Aurora Global"]
        DocDB["DocumentDB Global"]
        Cache["ElastiCache Global"]
        MSK["MSK Kafka"]
        OS["OpenSearch"]
        S3["S3"]
    end

    subgraph "Layer 5: Compute"
        EKS["EKS"]
    end

    subgraph "Layer 6: Edge"
        CF["CloudFront"]
        WAF["WAF"]
        R53["Route53"]
    end

    subgraph "Layer 7: Observability"
        CW["CloudWatch"]
        XRay["X-Ray"]
        Tempo["Tempo Storage"]
    end

    VPC --> SG
    KMS --> SM
    KMS --> Aurora
    KMS --> DocDB
    KMS --> Cache
    KMS --> MSK

    SG --> Aurora
    SG --> DocDB
    SG --> Cache
    SG --> MSK
    SG --> OS
    SG --> EKS

    VPC --> TGW
    VPC --> ALB
    VPC --> EKS

    SM --> Aurora
    SM --> DocDB
    SM --> MSK

    EKS --> Aurora
    EKS --> DocDB
    EKS --> Cache
    EKS --> MSK
    EKS --> OS

    ALB --> CF
    CF --> WAF
    CF --> R53

    EKS --> CW
    EKS --> XRay
    EKS --> Tempo
```

## Resource Status by Region

### us-east-1 (Primary Region)

| Category | Resource Count | Key Components |
|----------|---------------|----------------|
| Networking | ~30 | VPC, Subnets, NAT GW, Transit Gateway |
| Compute | ~45 | EKS Cluster, Node Groups, ALB |
| Data | ~80 | Aurora, DocumentDB, ElastiCache, MSK, OpenSearch |
| Security | ~35 | KMS, Secrets Manager, IAM, Security Groups |
| Edge | ~20 | CloudFront, WAF, Route53 |
| Observability | ~50 | CloudWatch, X-Ray, Tempo Storage |
| **Total** | **~260** | |

### us-west-2 (Secondary Region)

| Category | Resource Count | Key Components |
|----------|---------------|----------------|
| Networking | ~30 | VPC, Subnets, NAT GW, Transit Gateway |
| Compute | ~45 | EKS Cluster, Node Groups, ALB |
| Data | ~75 | Aurora (Read), DocumentDB, ElastiCache, MSK, OpenSearch |
| Security | ~35 | KMS, Secrets Manager, IAM, Security Groups |
| Observability | ~50 | CloudWatch, X-Ray, Tempo Storage |
| **Total** | **~235** | |

## Environment Structure

```
terraform/
├── environments/
│   └── production/
│       ├── us-east-1/          # Primary Region
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── terraform.tfvars
│       └── us-west-2/          # Secondary Region
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── terraform.tfvars
├── global/                     # Global Resources
│   ├── route53/
│   └── iam/
└── modules/                    # Reusable Modules
    ├── compute/
    ├── data/
    ├── edge/
    ├── networking/
    ├── observability/
    └── security/
```

## Provisioning Order

When deploying to multiple regions, resources must be provisioned in the following order considering dependencies:

1. **Global Resources**: Route53 Hosted Zone, IAM Roles
2. **us-east-1 Primary**: Full infrastructure (including global database primary)
3. **us-west-2 Secondary**: Full infrastructure (joining global databases as secondary)

:::caution Important Notes
- Running `terraform apply` simultaneously in both regions may cause state conflicts
- Always deploy the primary region first, then the secondary region
- Global databases (Aurora, DocumentDB, ElastiCache) are created in the primary region first, then joined by the secondary
:::

## Tagging Strategy

All resources have the following tags applied:

```hcl
default_tags {
  tags = {
    Environment = "production"
    Region      = var.region
    ManagedBy   = "terraform"
    Project     = "multi-region-mall"
  }
}
```

## Next Steps

- [Terraform Modules](/infrastructure/terraform-modules) - Detailed description of 17 modules
- [EKS Cluster](/infrastructure/eks-cluster) - Kubernetes cluster configuration
- [Databases](/infrastructure/databases/aurora-global) - Global database configuration

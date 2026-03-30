---
sidebar_position: 4
title: Terraform Structure
description: 3-Layer Terraform 구조 — shared, eks-az-a, eks-az-c
---

# Terraform Structure

3-Layer 구조로 공유 리소스(VPC, Data Stores)와 AZ별 리소스(EKS, NLB)를 분리합니다.

## Directory Layout

```
terraform/environments/production/ap-northeast-2/
├── shared/                     # Layer 1: VPC + Data Stores
│   ├── main.tf                # VPC, SG, KMS, Aurora, DocumentDB, ElastiCache,
│   │                          # MSK, OpenSearch, S3, Secrets Manager
│   ├── variables.tf
│   ├── outputs.tf             # vpc_id, subnet_ids, sg_ids → remote state
│   ├── terraform.tfvars
│   └── backend.tf             # S3 key: production/ap-northeast-2/shared/
│
├── eks-az-a/                   # Layer 2: EKS + NLB for AZ-A
│   ├── main.tf                # EKS(mall-apne2-az-a), ALB IRSA, NLB, OTel IRSA
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── backend.tf             # S3 key: production/ap-northeast-2/eks-az-a/
│
└── eks-az-c/                   # Layer 3: EKS + NLB for AZ-C
    ├── main.tf                # EKS(mall-apne2-az-c), ALB IRSA, NLB, OTel IRSA
    ├── variables.tf
    ├── terraform.tfvars
    └── backend.tf             # S3 key: production/ap-northeast-2/eks-az-c/
```

:::info State 참조
eks-az-a/c는 `terraform_remote_state.shared`를 통해 Layer 1의 VPC ID, Subnet IDs, SG IDs를 참조합니다. 3개의 독립 state file로 blast radius를 최소화합니다.
:::

## Layer 1: Shared

공유 VPC, 보안, 데이터 스토어를 관리합니다.

| Module | Resource | 특이사항 |
|--------|----------|---------|
| `vpc` | VPC, 2 AZ subnets (Public/Private/Data) | Private /20 (4,096 IPs for Karpenter) |
| `security_groups` | ALB, NLB, EKS, Data SGs | VPC CIDR에서만 접근 |
| `kms` | 5 CMKs (aurora, docdb, cache, msk, s3) | |
| `aurora` | 1 Writer + 2 Reader (AZ-A, AZ-C) | `is_primary=true` (독립 클러스터) |
| `documentdb` | 2 instances (Global Cluster secondary) | `is_primary=false`, source: us-east-1 |
| `elasticache` | 1 shard, 1 replica (Standalone) | Global Datastore 미참여 (독립) |
| `msk` | 4 brokers (2+2 per AZ) | Independent cluster |
| `opensearch` | 3 Master + 2 Data (2-AZ) | `create_service_linked_role=false` |
| `s3` | Static + Analytics buckets | Secondary (no replication) |

### Key Configuration (terraform.tfvars)

```hcl
environment = "production"
region      = "ap-northeast-2"

vpc_cidr           = "10.2.0.0/16"
availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]

public_subnet_cidrs  = ["10.2.1.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.16.0/20", "10.2.32.0/20"]   # /20 for Karpenter!
data_subnet_cidrs    = ["10.2.48.0/24", "10.2.49.0/24"]

eks_az_a_cluster_name = "mall-apne2-az-a"
eks_az_c_cluster_name = "mall-apne2-az-c"

docdb_global_cluster_identifier = "multi-region-mall-docdb"
```

### Data Store Configuration

```hcl
# Aurora: 독립 클러스터 (Global Cluster 미참여)
module "aurora" {
  is_primary                = true
  global_cluster_identifier = ""       # NOT joining global cluster
  reader_count              = 2
  reader_availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]
}

# DocumentDB: Global Cluster secondary
module "documentdb" {
  is_primary                = false    # Global secondary
  global_cluster_identifier = "multi-region-mall-docdb"
  source_region             = "us-east-1"
  instance_count            = 2
}

# ElastiCache: Standalone (NOT global)
module "elasticache" {
  is_primary                  = true
  global_replication_group_id = ""     # NOT joining global datastore
}

# MSK: 4 brokers for 2+2 AZ distribution
module "msk" {
  number_of_broker_nodes = 4
  broker_instance_type   = "kafka.m5.large"
}
```

## Layer 2/3: EKS per AZ

각 AZ에 독립 EKS 클러스터, NLB, IRSA 역할을 배포합니다.

### AZ-A (eks-az-a)

| Resource | Value |
|----------|-------|
| Cluster | `mall-apne2-az-a` |
| Subnet | `private_subnet_ids[0]` (AZ-A only) |
| NLB | `public_subnet_ids[0]` (AZ-A only) |
| Role Suffix | `-apne2-az-a` |
| IRSA | ALB Controller, OTel Collector, Tempo |

### AZ-C (eks-az-c)

| Resource | Value |
|----------|-------|
| Cluster | `mall-apne2-az-c` |
| Subnet | `private_subnet_ids[1]` (AZ-C only) |
| NLB | `public_subnet_ids[1]` (AZ-C only) |
| Role Suffix | `-apne2-az-c` |
| IRSA | ALB Controller, OTel Collector, Tempo |

### Remote State Reference

```hcl
# eks-az-a/main.tf
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "multi-region-mall-terraform-state"
    key    = "production/ap-northeast-2/shared/terraform.tfstate"
    region = "us-east-1"
  }
}

module "eks" {
  cluster_name       = "mall-apne2-az-a"
  vpc_id             = data.terraform_remote_state.shared.outputs.vpc_id
  private_subnet_ids = [data.terraform_remote_state.shared.outputs.private_subnet_ids[0]]
  # Single subnet = single AZ isolation
}
```

## State Management

| State | S3 Key | Resources |
|-------|--------|-----------|
| Shared | `production/ap-northeast-2/shared/terraform.tfstate` | VPC, Data Stores |
| EKS AZ-A | `production/ap-northeast-2/eks-az-a/terraform.tfstate` | EKS, NLB, IRSA |
| EKS AZ-C | `production/ap-northeast-2/eks-az-c/terraform.tfstate` | EKS, NLB, IRSA |

:::warning Apply 순서
반드시 `shared` → `eks-az-a` → `eks-az-c` 순서로 apply하세요. EKS 레이어가 shared의 outputs를 참조합니다.
:::

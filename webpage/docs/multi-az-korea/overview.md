---
sidebar_position: 1
title: Overview
description: ap-northeast-2 Multi Independent AZ 아키텍처 개요
---

# Multi Independent AZ Architecture

**ap-northeast-2 (Seoul) — AZ-A / AZ-C 독립 클러스터 + AZ-Local 데이터 접근**

## Executive Summary

한국 리전(ap-northeast-2)은 기존 Multi-Region(US) 아키텍처와 달리 **Multi Independent AZ** 패턴을 채택합니다. 하나의 VPC 내에서 **AZ-A**와 **AZ-C**에 각각 독립된 EKS 클러스터를 운영하여 **AZ-level blast radius isolation**과 **cross-AZ 데이터 전송 비용 절감**을 달성합니다.

데이터 스토어는 공유 VPC에 배포되되, 각 EKS 클러스터는 **AZ-local 엔드포인트**를 통해 같은 AZ의 데이터에 우선 접근합니다. Aurora Custom Endpoint, DocumentDB 개별 Instance Endpoint, ElastiCache RouteByLatency, MSK rack-aware 소비 패턴을 조합하여 구현합니다.

## Key Metrics

| Metric | Value |
|--------|-------|
| **EKS Clusters** | 2 (AZ별 독립) |
| **Terraform Layers** | 3 (shared + eks-az-a + eks-az-c) |
| **Shared VPC** | 1 (`10.2.0.0/16`) |
| **AZ-A** | ap-northeast-2a |
| **AZ-B** | Reserved (미사용) |
| **AZ-C** | ap-northeast-2c |

## Architecture Topology

```
┌────────────────────────────────────────────────────────────────────────────┐
│                      VPC 10.2.0.0/16 (Shared)                             │
│                                                                            │
│  ┌──────────────────────────┐    ┌──────────────────────────┐             │
│  │  AZ-A (ap-northeast-2a)  │    │  AZ-C (ap-northeast-2c)  │             │
│  │                          │    │                          │             │
│  │  ┌────────────────────┐  │    │  ┌────────────────────┐  │             │
│  │  │ EKS: mall-apne2-   │  │    │  │ EKS: mall-apne2-   │  │             │
│  │  │       az-a          │  │    │  │       az-c          │  │             │
│  │  │                    │  │    │  │                    │  │             │
│  │  │ NLB-A → API GW    │  │    │  │ NLB-C → API GW    │  │             │
│  │  │ → 20 Services     │  │    │  │ → 20 Services     │  │             │
│  │  │ Private 10.2.16/20│  │    │  │ Private 10.2.32/20│  │             │
│  │  │                    │  │    │  │                    │  │             │
│  │  │ Karpenter (2a only)│  │    │  │ Karpenter (2c only)│  │             │
│  │  └────────┬───────────┘  │    │  └────────┬───────────┘  │             │
│  │           │ AZ-local read │    │           │ AZ-local read │             │
│  └───────────┼──────────────┘    └───────────┼──────────────┘             │
│              ▼                                ▼                            │
│  ┌────────────────────────────────────────────────────────────┐           │
│  │              SHARED DATA LAYER (Data Subnets)              │           │
│  │                                                            │           │
│  │  Aurora 17.7    DocumentDB 8.0   ElastiCache (Valkey)     │           │
│  │  1W + 2R        Global Secondary  Standalone               │           │
│  │  Custom EP/AZ   Instance EP/AZ   RouteByLatency           │           │
│  │                                                            │           │
│  │  MSK (Kafka)    OpenSearch        S3                       │           │
│  │  4 brokers 2+2  3M + 2D (2-AZ)   Static + Analytics      │           │
│  │  client.rack    Independent       Secondary                │           │
│  └────────────────────────────────────────────────────────────┘           │
└────────────────────────────────────────────────────────────────────────────┘
```

## Multi-Region vs Multi Independent AZ

| 구분 | Multi-Region (US) | Multi Independent AZ (Korea) |
|------|-------------------|------------------------------|
| **리전** | us-east-1 + us-west-2 | ap-northeast-2 내 AZ-A + AZ-C |
| **VPC** | 리전별 독립 VPC | 1개 공유 VPC |
| **EKS** | 리전당 1 클러스터 | AZ당 1 클러스터 |
| **Data Pattern** | Write-Primary / Read-Local | AZ-local 읽기 + Shared Writer |
| **Failover** | Cross-region (Aurora Global) | Cross-AZ (동일 리전 내) |
| **Network** | Transit Gateway / VPC Peering | 동일 VPC (L2 레벨) |
| **비용 절감 대상** | Cross-region transfer | Cross-AZ transfer ($0.01/GB) |

## Design Principles

1. **AZ Isolation**: 각 AZ는 독립적으로 운영 가능해야 합니다 — 한쪽 AZ 장애가 다른 AZ에 영향을 주지 않습니다
2. **Shared Data**: 데이터 스토어는 VPC 레벨에서 공유하되, 접근은 AZ-local 우선입니다
3. **Backward Compatibility**: 모든 새 환경변수에 기본값 fallback을 설정하여 US 리전에서는 기존 동작을 유지합니다
4. **3-Layer Terraform**: shared (VPC+Data) → eks-az-a → eks-az-c 로 blast radius를 최소화합니다

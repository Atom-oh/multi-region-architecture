---
sidebar_position: 1
title: Deployment Overview
description: GitOps strategy overview, multi-region deployment pipeline diagram
---

# Deployment Overview

The multi-region shopping mall platform adopts the **GitOps** paradigm, using the Git repository as the Single Source of Truth. Infrastructure changes are managed with **Terraform**, and application deployments are managed with **ArgoCD** and **Kustomize**.

## Deployment Pipeline Overview

```mermaid
flowchart TB
    subgraph "Developer"
        DEV["Developer"]
        CODE["Code Change"]
    end

    subgraph "GitHub"
        PR["Pull Request"]
        MAIN["main branch"]
        GHA["GitHub Actions"]
    end

    subgraph "Terraform Pipeline"
        TF_PLAN["terraform plan"]
        TF_APPLY_E["terraform apply<br/>us-east-1"]
        TF_APPLY_W["terraform apply<br/>us-west-2"]
    end

    subgraph "Application Pipeline"
        BUILD["Docker Build"]
        ECR_E["ECR us-east-1"]
        ECR_W["ECR us-west-2"]
    end

    subgraph "ArgoCD"
        ARGO_E["ArgoCD<br/>us-east-1"]
        ARGO_W["ArgoCD<br/>us-west-2"]
    end

    subgraph "Kubernetes"
        EKS_E["EKS us-east-1"]
        EKS_W["EKS us-west-2"]
    end

    DEV -->|"git push"| CODE
    CODE -->|"create"| PR
    PR -->|"merge"| MAIN

    MAIN --> GHA

    GHA -->|"terraform/**"| TF_PLAN
    TF_PLAN --> TF_APPLY_E
    TF_APPLY_E -->|"depends on"| TF_APPLY_W

    GHA -->|"src/**, k8s/**"| BUILD
    BUILD --> ECR_E
    BUILD --> ECR_W

    ECR_E --> ARGO_E
    ECR_W --> ARGO_W

    ARGO_E --> EKS_E
    ARGO_W --> EKS_W
```

## GitOps Principles

### 1. Declarative Configuration

All infrastructure and application states are declared as code:

```
multi-region-architecture/
├── terraform/                    # Infrastructure code
│   ├── environments/
│   │   └── production/
│   │       ├── us-east-1/       # Primary region
│   │       └── us-west-2/       # Secondary region
│   └── modules/                  # Reusable modules
├── k8s/                          # Kubernetes manifests
│   ├── base/                     # Common settings
│   ├── services/                 # Service deployments
│   ├── overlays/                 # Regional overlays
│   │   ├── us-east-1/
│   │   └── us-west-2/
│   └── infra/                    # Infrastructure components
└── .github/workflows/            # CI/CD pipelines
```

### 2. Version Controlled

- All changes are tracked via Git commits
- Changes reviewed through Pull Requests
- Rollbacks performed via Git revert

### 3. Automated

- Automatic Plan/Preview on PR creation
- Automatic deployment on merge to main branch
- ArgoCD continuously synchronizes Git state with cluster state

### 4. Auditable

- Track change history via Git history
- Review deployment records via GitHub Actions logs
- ArgoCD synchronization history

## Deployment Flow

### Infrastructure Changes (Terraform)

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant GHA as GitHub Actions
    participant TF as Terraform
    participant AWS as AWS

    Dev->>GH: Push to feature branch
    Dev->>GH: Create PR
    GH->>GHA: Trigger workflow

    rect rgb(200, 220, 240)
        Note over GHA,TF: PR Phase
        GHA->>TF: terraform init
        GHA->>TF: terraform plan (us-east-1)
        TF-->>GHA: Plan output
        GHA->>GH: Comment plan result
        GHA->>TF: terraform plan (us-west-2)
        TF-->>GHA: Plan output
        GHA->>GH: Comment plan result
    end

    Dev->>GH: Merge PR to main

    rect rgb(220, 240, 200)
        Note over GHA,AWS: Apply Phase
        GH->>GHA: Trigger on main
        GHA->>TF: terraform apply (us-east-1)
        TF->>AWS: Create/Update resources
        AWS-->>TF: Done
        GHA->>TF: terraform apply (us-west-2)
        TF->>AWS: Create/Update resources
        AWS-->>TF: Done
    end
```

### Application Changes

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant GHA as GitHub Actions
    participant ECR as ECR
    participant Argo as ArgoCD
    participant K8s as Kubernetes

    Dev->>GH: Push code change
    Dev->>GH: Merge to main
    GH->>GHA: Trigger workflow

    rect rgb(200, 220, 240)
        Note over GHA,ECR: Build Phase
        GHA->>GHA: Detect changed services
        GHA->>GHA: Build Docker image
        GHA->>ECR: Push to us-east-1
        GHA->>ECR: Push to us-west-2
    end

    rect rgb(220, 240, 200)
        Note over Argo,K8s: Deploy Phase (us-east-1)
        Argo->>GH: Detect Git change
        Argo->>K8s: Apply manifests
        K8s-->>Argo: Sync complete
    end

    rect rgb(240, 220, 200)
        Note over Argo,K8s: Deploy Phase (us-west-2)
        Argo->>GH: Detect Git change
        Argo->>K8s: Apply manifests
        K8s-->>Argo: Sync complete
    end
```

## Environment Configuration

### Regional Roles

| Region | Role | Deployment Order | Database Mode |
|--------|------|------------------|---------------|
| **us-east-1** | Primary | 1st | Writer |
| **us-west-2** | Secondary | 2nd (after us-east-1 completes) | Reader / Failover |

### Deployment Order

```mermaid
flowchart LR
    subgraph "Phase 1"
        E1["us-east-1<br/>Primary"]
    end

    subgraph "Phase 2"
        W2["us-west-2<br/>Secondary"]
    end

    subgraph "Validation"
        V1["Health Check"]
        V2["Smoke Test"]
    end

    E1 -->|"After success"| W2
    W2 --> V1
    V1 --> V2
```

:::caution Deployment Order Important
When making infrastructure changes, you must deploy to us-east-1 (Primary) first. For global databases, the Primary region creates the global cluster, then the Secondary joins.
:::

## Tool Stack

| Tool | Purpose | Version |
|------|---------|---------|
| **Terraform** | Infrastructure provisioning | 1.7.0 |
| **ArgoCD** | Kubernetes GitOps | 2.10.x |
| **Kustomize** | Kubernetes manifest management | 5.x |
| **GitHub Actions** | CI/CD pipeline | - |
| **Docker** | Container image builds | - |
| **ECR** | Container registry | - |

## Branch Strategy

```mermaid
gitGraph
    commit id: "initial"
    branch feature/add-payment
    commit id: "feat: add payment"
    commit id: "test: payment tests"
    checkout main
    merge feature/add-payment id: "merge: payment" tag: "v1.2.0"
    commit id: "deploy to prod"
```

### Branch Rules

| Branch | Purpose | Protection Rules |
|--------|---------|------------------|
| `main` | Production deployment | PR required, 1+ reviewers, CI must pass |
| `feature/*` | Feature development | - |
| `fix/*` | Bug fixes | - |
| `hotfix/*` | Emergency fixes | Branch from main, can merge directly |

## Rollback Strategy

### Infrastructure Rollback

```bash
# Revert to previous state in Git
git revert <commit-hash>
git push origin main

# Or rollback to a specific version directly
cd terraform/environments/production/us-east-1
terraform plan -target=module.eks
terraform apply -target=module.eks
```

### Application Rollback

```bash
# Using ArgoCD CLI
argocd app rollback <app-name> <revision>

# Or Git revert
git revert <commit-hash>
git push origin main
# ArgoCD automatically syncs to previous state
```

## Next Steps

- [GitOps - ArgoCD](/deployment/gitops-argocd) - ArgoCD ApplicationSet details
- [CI/CD Pipeline](/deployment/ci-cd-pipeline) - GitHub Actions workflow
- [Kustomize Overlays](/deployment/kustomize-overlays) - Regional configuration
- [Rollout Strategy](/deployment/rollout-strategy) - Deployment and rollback strategy

---
sidebar_position: 1
title: 배포 개요
description: GitOps 전략 개요, 멀티 리전 배포 파이프라인 다이어그램
---

# 배포 개요

멀티 리전 쇼핑몰 플랫폼은 **GitOps** 패러다임을 채택하여 Git 저장소를 단일 진실 공급원(Single Source of Truth)으로 사용합니다. 인프라 변경은 **Terraform**으로, 애플리케이션 배포는 **ArgoCD**와 **Kustomize**로 관리합니다.

## 배포 파이프라인 개요

```mermaid
flowchart TB
    subgraph "Developer"
        DEV["개발자"]
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

## GitOps 원칙

### 1. 선언적 구성 (Declarative)

모든 인프라와 애플리케이션 상태는 코드로 선언됩니다:

```
multi-region-architecture/
├── terraform/                    # 인프라 코드
│   ├── environments/
│   │   └── production/
│   │       ├── us-east-1/       # 프라이머리 리전
│   │       └── us-west-2/       # 세컨더리 리전
│   └── modules/                  # 재사용 모듈
├── k8s/                          # Kubernetes 매니페스트
│   ├── base/                     # 공통 설정
│   ├── services/                 # 서비스별 배포
│   ├── overlays/                 # 리전별 오버레이
│   │   ├── us-east-1/
│   │   └── us-west-2/
│   └── infra/                    # 인프라 컴포넌트
└── .github/workflows/            # CI/CD 파이프라인
```

### 2. 버전 관리 (Versioned)

- 모든 변경사항은 Git 커밋으로 추적
- Pull Request를 통한 변경 리뷰
- 롤백은 Git revert로 수행

### 3. 자동화 (Automated)

- PR 생성 시 자동 Plan/Preview
- main 브랜치 머지 시 자동 배포
- ArgoCD가 Git 상태와 클러스터 상태를 지속적으로 동기화

### 4. 감사 가능 (Auditable)

- Git 히스토리로 변경 이력 추적
- GitHub Actions 로그로 배포 기록 확인
- ArgoCD 동기화 히스토리

## 배포 흐름

### 인프라 변경 (Terraform)

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

### 애플리케이션 변경

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

## 환경 구성

### 리전별 역할

| 리전 | 역할 | 배포 순서 | 데이터베이스 모드 |
|------|------|----------|-----------------|
| **us-east-1** | Primary | 1번째 | Writer |
| **us-west-2** | Secondary | 2번째 (us-east-1 완료 후) | Reader / Failover |

### 배포 순서

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

    E1 -->|"성공 후"| W2
    W2 --> V1
    V1 --> V2
```

:::caution 배포 순서 중요
인프라 변경 시 반드시 us-east-1(Primary)을 먼저 배포해야 합니다. 글로벌 데이터베이스의 경우 Primary 리전에서 글로벌 클러스터가 생성된 후 Secondary가 조인합니다.
:::

## 도구 스택

| 도구 | 용도 | 버전 |
|------|------|------|
| **Terraform** | 인프라 프로비저닝 | 1.7.0 |
| **ArgoCD** | Kubernetes GitOps | 2.10.x |
| **Kustomize** | Kubernetes 매니페스트 관리 | 5.x |
| **GitHub Actions** | CI/CD 파이프라인 | - |
| **Docker** | 컨테이너 이미지 빌드 | - |
| **ECR** | 컨테이너 레지스트리 | - |

## 브랜치 전략

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

### 브랜치 규칙

| 브랜치 | 용도 | 보호 규칙 |
|--------|------|----------|
| `main` | 프로덕션 배포 | PR 필수, 리뷰 1명 이상, CI 통과 |
| `feature/*` | 기능 개발 | - |
| `fix/*` | 버그 수정 | - |
| `hotfix/*` | 긴급 수정 | main에서 분기, 바로 머지 가능 |

## 롤백 전략

### 인프라 롤백

```bash
# Git에서 이전 상태로 되돌리기
git revert <commit-hash>
git push origin main

# 또는 특정 버전으로 직접 롤백
cd terraform/environments/production/us-east-1
terraform plan -target=module.eks
terraform apply -target=module.eks
```

### 애플리케이션 롤백

```bash
# ArgoCD CLI 사용
argocd app rollback <app-name> <revision>

# 또는 Git revert
git revert <commit-hash>
git push origin main
# ArgoCD가 자동으로 이전 상태로 동기화
```

## 다음 단계

- [GitOps - ArgoCD](/deployment/gitops-argocd) - ArgoCD ApplicationSet 상세
- [CI/CD 파이프라인](/deployment/ci-cd-pipeline) - GitHub Actions 워크플로우
- [Kustomize 오버레이](/deployment/kustomize-overlays) - 리전별 구성
- [롤아웃 전략](/deployment/rollout-strategy) - 배포 및 롤백 전략

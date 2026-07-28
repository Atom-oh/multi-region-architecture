# ADR-003: Korea mgmt 클러스터 소유권을 AWS-Demo-Platform으로 이관, spoke는 live lookup

## Status

Accepted (2026-07-28).

## Context

`mall-apne2-mgmt`(Korea 관리 클러스터 — 관측성, ArgoCD, self-hosted runner)의 Terraform은
이 repo(`terraform/environments/production/ap-northeast-2/eks-mgmt/`)와
`AWS-Demo-Platform`(`infra/eks-mgmt/`) 양쪽에 존재했다. 두 코드는 **동일한 state 객체**를
가리킨다:

| | 값 |
|---|---|
| bucket | `multi-region-mall-terraform-state` |
| key | `production/ap-northeast-2/eks-mgmt/terraform.tfstate` |
| lock table | `multi-region-mall-terraform-locks` |

즉 한 리소스 집합에 writer가 둘인 상태였다. `AWS-Demo-Platform`은 2026-06-24
(`ed97945` 코드 이관, `122196a` 단독 소유 선언)부터 이 클러스터를 실제로 apply하고 있고,
ArgoCD 허브·runner 이미지 빌드도 그쪽에서 관리한다. 이 repo는 배포 아키텍처와 워크로드
클러스터(`eks-az-a`, `eks-az-c`)를 담당한다.

두 workload spoke는 mgmt의 클러스터 SG를 필요로 한다 — ArgoCD가 허브에서 spoke API
server로 접근하기 위한 ingress 규칙(`argocd_security_group_id`)이다. 기존에는
`data "terraform_remote_state" "eks_mgmt"`로 읽었다.

## Decision

1. **소유권은 `AWS-Demo-Platform` 단독.** 이 repo에서 `eks-mgmt/` 레이어를 삭제한다.
   `terraform state mv`/`rm`은 필요 없다 — state 객체는 이동하지 않고, 바뀌는 것은
   *reader*뿐이다.

2. **spoke는 remote state가 아니라 live lookup을 쓴다.**
   `data "aws_eks_cluster" "mgmt"`. 다른 repo의 state 파일 내부 구조에 의존하는 것보다
   AWS API가 안정적인 계약이며, 그쪽 레이어 구성이 바뀌어도(모듈 이름, output 이름)
   여기가 깨지지 않는다. 대가는 plan 시점에 mgmt가 **살아 있어야 한다**는 것이다
   (아래 Consequences).

3. **이름만으로 신뢰하지 않는다.** lookup에 세 개의 `postcondition`을 건다 —
   VPC가 이 리전 shared VPC와 일치하는지, 이 플랫폼이 모든 클러스터에 찍는
   `ManagedBy=terraform` / `Project=multi-region-mall` 태그가 있는지, 그리고 클러스터
   SG가 실제로 비어 있지 않은지(비면 EKS 모듈이 ingress 규칙을 조용히 생략한다).
   그 SG는 workload 클러스터 API server의 ingress trust boundary가 되므로, 계정 내에서
   같은 이름의 클러스터를 만들 수 있는 주체가 자동으로 신뢰되면 안 된다.

4. **모든 가드에 대칭적인 escape hatch를 둔다.** 해제 수단 없는 가드는 외부 repo가
   정당하게 mgmt를 옮겼을 때 이 repo에서 고칠 수 없는 영구 plan 실패가 된다.
   - `var.expected_mgmt_vpc_id` — 기본값은 `""`이며, 이때 기대 VPC는 shared 레이어의
     `vpc_id`로 계산된다(local). VPC 가드 해제용.
   - `var.expected_mgmt_tags` — 기본값은 위 두 태그. `{}`로 두면 태그 가드 해제.
   - `var.mgmt_cluster_security_group_id` — 기본값 `null`(= live lookup).
     non-null이면 data source의 `count`가 0이 되어 **API read 자체와 postcondition
     전체가 사라진다.** 이것이 break-glass의 실제 경로다 — data 블록을 무조건
     선언해두면 인시던트 중 `.tf`를 편집하는 것 외에 방법이 없다.
   - `var.mgmt_cluster_name` — 이름 변경 대응. 단 `shared/`의
     `describable_cluster_names`와 짝이라 2단계 절차다(아래 Consequences).

5. **"여기서 apply하지 말 것"을 CI 경로에서는 IAM으로 승격한다.** `github-actions-role`에
   해당 state key에 대한 `s3:PutObject`/`s3:DeleteObject` 명시적 **Deny**를 추가한다
   (`externally_owned_state_keys`). 문서 경고는 통제가 아니다. 같은 정책에
   `ap-northeast-2`의 `mall-apne2-mgmt` ARN으로 스코프한 `eks:DescribeCluster`
   **Allow**를 추가한다 (`describable_cluster_names`) — 이 권한 없이는 spoke의
   *모든* plan이 실패한다. 이 Deny의 한계는 명시해둔다: identity policy이므로
   **그 role 하나에만** 걸린다. 사람이 admin 자격증명으로, 혹은 다른 role로 같은
   객체를 쓰는 것은 여전히 가능하고, DynamoDB lock row 쓰기와 mgmt 리소스 자체의
   변경도 막지 않는다. 완전한 차단이 필요하면 버킷 정책으로 올려야 한다.

## Consequences

**얻는 것**

- state 객체당 writer 1명. CI 경로(= `github-actions-role`)에서는 동시 apply로 state가
  깨질 경로가 IAM으로 차단된다. 사람의 admin 세션은 관례로만 막힌다.
- cross-repo state 스키마 의존 제거. mgmt 레이어 리팩터링이 이 repo를 깨뜨리지 않는다.
- 이름 스쿼팅으로 trust boundary를 넘는 경로가 VPC + 태그 assert로 막힌다.

**잃는 것 / 새로 관리해야 하는 것**

- **plan이 mgmt live 존재에 결합된다.** mgmt가 삭제·장애 상태거나
  `eks:DescribeCluster`가 실패하면, 트래픽을 받는 workload 클러스터의 모든 Terraform
  작업이 막힌다. Break-glass는 `-var mgmt_cluster_security_group_id=...` 한 줄이다
  (Decision 4). 빈 문자열을 주면 EKS 모듈이 해당 ingress 규칙을 아예 만들지 않는다
  (`count = var.argocd_security_group_id != "" ? 1 : 0`). 워크로드 트래픽 경로
  (CloudFront → NLB → api-gateway)는 이 SG와 무관하므로 영향받지 않는다 — 끊기는 것은
  GitOps sync뿐이다. 실행 명령은 region README의 Runbooks가 정본이다.

- **mgmt 이름 변경이 2단계 절차가 된다.** `var.mgmt_cluster_name`(spoke)과
  `describable_cluster_names`(`shared/`)가 같은 클러스터를 두 레이어에서 지칭한다.
  새 이름을 `shared/`에 먼저 추가해 apply하지 않으면, spoke는 postcondition에
  도달하기 전에 `AccessDenied`로 죽는다.

- **mgmt 재생성 시 spoke ingress가 stale해진다.** mgmt 클러스터를 replace하면
  EKS-managed SG ID가 바뀌고, 두 spoke를 재-apply하기 전까지 ArgoCD → spoke API 접근이
  조용히 끊긴다(워크로드는 계속 동작하므로 다음 sync 실패로만 드러난다). 절차는
  region README의 Runbooks 참조 — 요약하면 mgmt apply → 이 repo에서 spoke 2개
  (`eks-az-a`, `eks-az-c`) apply → mgmt에서 `argocd cluster list`로 두 spoke 연결 확인.

- **shared layer의 output 일부가 외부 계약이 된다.** `AWS-Demo-Platform`의 mgmt 레이어가
  이 repo의 shared state를 읽는다: `vpc_id`, `private_subnet_ids`,
  `internal_observability_nlb_security_group_id`, `kms_key_arns["s3"]`.
  이 이름·타입은 breaking change 금지 대상이다.

- **이 repo가 더 이상 만들지 않는 것 전체 목록.** 삭제된 `eks-mgmt/` 레이어가 소유했던
  리소스는 이제 전부 `AWS-Demo-Platform`이 만든다:
  `module "eks"`, `module "alb"`, `module "otel_collector_irsa"`,
  `module "tempo_storage"`(mgmt 중앙 Tempo S3 + IRSA),
  `aws_iam_role.ci_runner` + inline/attached 정책 6개
  (`ci_runner_ecr`, `ci_runner_bedrock`, `ci_runner_cloudfront`, `ci_runner_ecs`,
  `ci_runner_cdk_deploy`, `ReadOnlyAccess`/`AmazonS3FullAccess` attachment),
  그리고 `aws_eks_pod_identity_association.ci_runner` 10개(runner SA당 1개).
  workload 클러스터의 per-AZ `tempo_storage`/`otel_collector_irsa`/`alb`는 이 repo에 남는다.
  `AWS-Demo-Platform`의 `infra/eks-mgmt`는 이 집합의 superset이다(추가로
  `ci_runner_ami_build`를 가진다) — 그래서 이관에 destroy가 없다.

## References

- `AWS-Demo-Platform` `ed97945` (코드 이관), `122196a` (단독 소유 선언, 2026-06-24)
- `terraform/environments/production/ap-northeast-2/README.md` — 레이어 표, apply 순서,
  Runbooks(break-glass·재생성 절차의 정본)
- `terraform/modules/security/iam/github-actions.tf` — `describable_cluster_names`,
  `externally_owned_state_keys`
- `terraform/environments/production/ap-northeast-2/eks-az-a/main.tf`,
  `terraform/environments/production/ap-northeast-2/eks-az-c/main.tf` — live lookup과
  postcondition 3개
- `terraform/environments/production/ap-northeast-2/shared/main.tf` — `module "iam"` 호출

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
| lock table | `multi-region-mall-terraform-lock` |

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

3. **이름만으로 신뢰하지 않는다.** lookup에 두 개의 `postcondition`을 건다 —
   VPC가 이 리전 shared VPC와 일치하는지, 그리고 이 플랫폼이 모든 클러스터에 찍는
   `ManagedBy=terraform` / `Project=multi-region-mall` 태그가 있는지. 그 SG는 workload
   클러스터 API server의 ingress trust boundary가 되므로, 계정 내에서 같은 이름의
   클러스터를 만들 수 있는 주체가 자동으로 신뢰되면 안 된다.

4. **escape hatch를 둔다.** `var.expected_mgmt_vpc_id`(기본값 = shared VPC).
   외부 repo가 정당하게 mgmt를 다른 VPC로 재구축했을 때, 이 repo에서 해제할 수단이
   없으면 가드는 영구 plan 실패가 된다. `var.mgmt_cluster_name`도 같은 이유로 변수화한다.

5. **"여기서 apply하지 말 것"을 IAM으로 승격한다.** `github-actions-role`에
   해당 state key에 대한 `s3:PutObject`/`s3:DeleteObject` 명시적 **Deny**를 추가한다
   (`externally_owned_state_keys`). 문서 경고는 통제가 아니다. 같은 정책에
   `mall-apne2-mgmt` ARN으로 스코프한 `eks:DescribeCluster` **Allow**를 추가한다
   (`describable_cluster_names`) — 이 권한 없이는 spoke의 *모든* plan이 실패한다.

## Consequences

**얻는 것**

- state 객체당 writer 1명. 동시 apply로 state가 깨질 경로가 IAM 수준에서 차단된다.
- cross-repo state 스키마 의존 제거. mgmt 레이어 리팩터링이 이 repo를 깨뜨리지 않는다.
- 이름 스쿼팅으로 trust boundary를 넘는 경로가 VPC + 태그 assert로 막힌다.

**잃는 것 / 새로 관리해야 하는 것**

- **plan이 mgmt live 존재에 결합된다.** mgmt가 삭제·장애 상태거나
  `eks:DescribeCluster`가 실패하면, 트래픽을 받는 workload 클러스터의 모든 Terraform
  작업이 막힌다. Break-glass: `argocd_security_group_id`가 빈 문자열이면 EKS 모듈이
  해당 ingress 규칙을 만들지 않으므로(`count = var.argocd_security_group_id != "" ? 1 : 0`),
  인시던트 중에는 `data` 블록 참조를 SG ID 리터럴로 임시 치환하거나 해당 인자를 비워
  apply할 수 있다. 워크로드 트래픽 경로(CloudFront → NLB → api-gateway)는 이 SG와
  무관하므로 영향받지 않는다 — 끊기는 것은 GitOps sync뿐이다.

- **mgmt 재생성 시 spoke ingress가 stale해진다.** mgmt 클러스터를 replace하면
  EKS-managed SG ID가 바뀌고, 두 spoke를 재-apply하기 전까지 ArgoCD → spoke API 접근이
  조용히 끊긴다(워크로드는 계속 동작하므로 다음 sync 실패로만 드러난다). 재생성 절차:
  ① `AWS-Demo-Platform`에서 mgmt apply → ② 이 repo에서 `eks-az-a`, `eks-az-c` apply →
  ③ mgmt에서 `argocd app list`로 spoke 3개 cluster 연결 확인.

- **shared layer의 output 일부가 외부 계약이 된다.** `AWS-Demo-Platform`의 mgmt 레이어가
  이 repo의 shared state를 읽는다: `vpc_id`, `private_subnet_ids`,
  `internal_observability_nlb_security_group_id`, `kms_key_arns["s3"]`.
  이 이름·타입은 breaking change 금지 대상이다.

- **Korea 중앙 관측성 스토리지 소유처가 외부로 이동한다.** mgmt에 있던
  `tempo_storage`(S3 + IRSA)와 OTel collector IRSA는 이제 `AWS-Demo-Platform`이 만든다.
  workload 클러스터의 per-AZ `tempo_storage`/`otel_collector_irsa`는 이 repo에 남는다.

## References

- `AWS-Demo-Platform` `ed97945` (코드 이관), `122196a` (단독 소유 선언, 2026-06-24)
- `terraform/environments/production/ap-northeast-2/README.md` — 레이어 표와 apply 순서
- `terraform/modules/security/iam/github-actions.tf` — `describable_cluster_names`,
  `externally_owned_state_keys`

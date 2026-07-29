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

3. **이름만으로 신뢰하지 않는다.** lookup에 네 개의 `postcondition`을 건다 —
   VPC가 이 리전 shared VPC와 일치하는지, 이 플랫폼이 모든 클러스터에 찍는
   `ManagedBy=terraform` / `Project=multi-region-mall` 태그가 있는지, 그리고 클러스터
   SG가 실제로 비어 있지 않은지(비면 EKS 모듈이 ingress 규칙을 조용히 생략한다),
   그리고 status가 `ACTIVE` 또는 `UPDATING`인지. `UPDATING`을 허용하는 것은 의도적이다 —
   control-plane 업그레이드는 10~40분간 그 상태를 반환하면서 cluster SG를 바꾸지 않으므로,
   `ACTIVE`만 통과시키면 외부 repo의 정기 유지보수 창 동안 이 레이어의 모든 plan이
   실패하고 운영자가 매번 break-glass를 쓰게 되어 해제 신호가 노이즈가 된다.
   `DELETING`/`FAILED` 클러스터도 DescribeCluster에 응답하고 SG를 그대로 들고 있어서,
   이 가드 없이는 철거 중인 클러스터의 SG를 계속 신뢰한다. 이 가드에는 개별 release
   변수가 없다 — lookup 자체를 건너뛰는 것이 유일한 우회로다.
   그 SG는 workload 클러스터 API server의 ingress trust boundary가 되므로, 계정 내에서
   같은 이름의 클러스터를 만들 수 있는 주체가 자동으로 신뢰되면 안 된다.

4. **모든 가드에 대칭적인 escape hatch를 둔다.** 해제 수단 없는 가드는 외부 repo가
   정당하게 mgmt를 옮겼을 때 이 repo에서 고칠 수 없는 영구 plan 실패가 된다.
   - `var.expected_mgmt_vpc_id` — 기본값은 `""`이며, 이때 기대 VPC는 shared 레이어의
     `vpc_id`로 계산된다(local). VPC 가드 해제용.
   - `var.expected_mgmt_tags` — 기본값은 위 두 태그. `{}`로 두면 태그 가드 해제.
   - `var.mgmt_cluster_security_group_id` — 기본값 `null`(= live lookup).
     non-null이면 data source의 `count`가 0이 되어 **cluster read 자체와
     postcondition 전체가 사라진다.** 대신 값이 빈 문자열이 아니면
     `data "aws_security_group" "mgmt_override"`가 그 SG를 조회해 shared VPC 소속인지
     assert한다. 비교 대상은 shared VPC가 아니라 `local.expected_mgmt_vpc_id`다 —
     lookup 경로가 이미 relocation을 허용하는데 override 경로만 shared VPC를 강제하면
     "mgmt가 peered VPC로 정당하게 이사한 뒤 장애"라는, 정확히 break-glass가 필요한
     상황에서 알려진 SG를 쓸 수 없게 된다. 여기에 `kubernetes.io/cluster/<name>=owned`
     태그 assert를 더한다. VPC 소속만으로는 통제가 약하다 — 같은 VPC에 ALB/NLB/앱/데이터
     계층 SG가 전부 있으므로 그중 아무 SG나 workload API server ingress source가 될 수
     있다. EKS가 클러스터 관리 SG에 자동으로 붙이는 태그라 break-glass 비용은 없다.
     `aws:eks:cluster-name`이 아니다 — EKS가 같이 붙이고 읽기도 더 좋지만 여기서는
     쓸 수 없다: AWS provider가 data source의 `tags` 맵에서 `aws:` prefix 시스템 태그를
     걸러내므로 `self.tags["aws:eks:cluster-name"]`은 항상 부재이고, 그러면 이 assert가
     **모든** SG에 대해 실패한다 — 즉 가드가 존재 이유인 인시던트에서만 발동한다.
     provider 6.52.0으로 live mgmt 클러스터 SG를 실측: DescribeSecurityGroups는
     `aws:eks:cluster-name` 포함 4개를 반환하는데 Terraform은 3개만 노출하고 정확히
     그 하나를 버린다.
     SG 조회는 mgmt 클러스터가 죽어도 응답하므로 override의 목적도 해치지 않는다. 이것이 break-glass의 실제 경로다 — data 블록을 무조건
     선언해두면 인시던트 중 `.tf`를 편집하는 것 외에 방법이 없다.
     앞의 세 가드를 한 번에 무력화하는 값이고 `TF_VAR_*` 환경변수만으로도 설정되므로,
     두 가지를 붙여 흔적을 남긴다: `sg-` 형식 `validation`(오타가 apply까지 가지
     않게), 그리고 `check "mgmt_guards_engaged"` + `output "mgmt_guards_released"` —
     `check`는 plan을 실패시키지 않고 경고만 내는 유일한 구문이라 해제된 plan이
     정상 plan과 똑같이 보이지 않게 한다. `check`와 output은 네 개의 trust 입력 **전부**를
     본다 — `TF_VAR_expected_mgmt_tags='{}'`, `TF_VAR_expected_mgmt_vpc_id=vpc-...`,
     `TF_VAR_mgmt_cluster_name=...`도 같은 trust boundary를 넓히는데, override만
     감지하면 그 경로들의 plan은 정상 plan과 완전히 동일하게 보인다.
     `mgmt_cluster_name`이 목록에 있는 이유는 그것이 단순 레이블이 아니라 trust
     입력이기 때문이다 — override 경로가 SG의 `aws:eks:cluster-name`을 이 값과
     비교하므로, override와 name을 같이 넘기면 다른 클러스터의 SG가 통과한다. output은 해제된 가드 목록을 state에 남겨 사후
     감사가 break-glass apply를 구분할 수 있게 한다. 단 이 output은 *현재* state의
     값이므로 이후 정상 apply가 빈 리스트로 덮어쓴다 — 지나간 break-glass를 되짚으려면
     state 버킷의 버저닝이나 CloudTrail이 필요하고, output 자체는 "지금 해제 상태인가"
     신호로 읽어야 한다(값은 bool이 아니라 해제된 가드 목록이다).
   - `var.mgmt_cluster_name` — 이름 변경 대응. 단 `shared/`의
     `describable_cluster_names`와 짝이라 2단계 절차다(아래 Consequences).
     이 변수는 위 `check`/output의 감시 대상이기도 하다.

   가드 전체(`data` 2개, postcondition 6개, `check`, `released_guards`)는
   `terraform/modules/security/mgmt-cluster-trust`에 두고 양 spoke가 호출한다. 두 spoke가
   문자 단위로 같은 로직을 필요로 하는데, 복제해두면 한쪽만 수정되는 drift가 리뷰에서
   보이지 않는다 — API server에 누가 닿을 수 있는지를 정하는 코드에는 맞지 않는 실패
   양식이다.

   trust 입력 **네 개 전부**(`mgmt_cluster_name`, `expected_mgmt_vpc_id`,
   `expected_mgmt_tags`, break-glass override)가 spoke 변수가 아니라 `shared/`의
   변수이고, spoke는 그것을 remote state output으로 읽는다. spoke별 변수면 한쪽만
   해제하고 다른 쪽을 잊는 것이 가능한데, 두 클러스터는 같은 weighted NLB 뒤에서 같은
   Aurora/DocumentDB primary를 공유하므로 ArgoCD 도달성이 갈리면 스키마 마이그레이션이
   fleet의 절반에만 도달한다. "양쪽에 같은 값을 넣으라"는 문서 문장은 통제가 아니다 —
   override만 올리고 나머지 셋을 spoke에 두는 것도 같은 이유로 부족하다.

   단 single-sourcing이 보장하는 것은 **값의 단일화**뿐이다: 두 spoke가 서로 다른 것을
   신뢰하도록 요구받는 경로가 없어진다. 실제 수렴은 보장하지 않는다 — 각 spoke가 자기
   apply를 해야 새 값을 집어가므로 한쪽만 apply된 창이 존재하고, 그 창은
   `scripts/check-mgmt-guards.sh`가 두 spoke의 `mgmt_guards_released`를 비교해서만
   잡힌다. break-glass 값은 `-var`가 아니라 `shared/terraform.tfvars`에 커밋한다:
   명령줄로 넘기면 이 레이어의 다음 무관한 apply가 조용히 `null`로 되돌리고
   `released_guards` 흔적까지 지운다.

   `check`는 정의상 plan을 실패시키지 않으므로 가드 해제는 경고로만 남는다. 그 경고를
   종료 코드로 바꾸는 것이 `scripts/check-mgmt-guards.sh`다 — 두 spoke의
   `mgmt_guards_released`가 비어 있는지, 그리고 서로 같은지(=양쪽 apply 완료)를 확인하고
   `argocd cluster list`로 실제 도달성까지 본다. 수동 실행이다: 이 저장소에 terraform
   apply를 하는 CI 경로 자체가 없고(모든 apply가 사람 손), 리뷰 지적 하나로 프로덕션에
   무기한 도는 스케줄 자동화를 새로 들이지 않는다.

5. **"여기서 apply하지 말 것"을 CI 경로에서는 IAM으로 승격한다.** `github-actions-role`에
   해당 state key에 대한 `s3:GetObject`/`s3:GetObjectVersion`/`s3:PutObject`/
   `s3:PutObjectAcl`/`s3:AbortMultipartUpload`/`s3:DeleteObject`/
   `s3:DeleteObjectVersion` 명시적
   **Deny**를 추가한다 (`externally_owned_state_keys`). read까지 막는 이유는 live
   lookup이 remote state read를 대체해 이 repo에 그 state를 읽을 이유가 남지 않았고,
   state 파일이 버킷에서 가장 밀도 높은 시크릿이기 때문이다. 객체만 막고 lock row를
   두면 절반만 막힌 셈이라 — 외부 repo가 lock을 잡은 동안 row를 지우면 동시 apply가
   가능해져 방금 보호한 객체가 깨진다 — `dynamodb:LeadingKeys`로 그 state의
   lock row(`<bucket>/<key>`와 `-md5` digest row)에만 스코프한 write Deny도 함께
   건다. Terraform 1.10+의 S3 native locking(`use_lockfile`)으로 넘어가면 lock이
   DynamoDB row가 아니라 `<key>.tflock` **객체**가 되므로, 그때는
   `externally_owned_state_keys`의 S3 Deny에 `.tflock` 접미사 리소스를 추가해야
   한다 — 현재 backend 설정은 DynamoDB 방식이라 아직 해당 없음. lock 테이블은 이 repo의 모든 레이어가 공유하므로 테이블 전체 Deny는 불가. 문서 경고는 통제가 아니다. 같은 정책에
   `ap-northeast-2`의 `mall-apne2-mgmt` ARN으로 스코프한 `eks:DescribeCluster`
   **Allow**를 추가한다 (`describable_cluster_names`) — 이 권한 없이는 spoke의
   *모든* plan이 실패한다. 이 Deny의 한계는 명시해둔다: identity policy이므로
   **그 role 하나에만** 걸린다. 사람이 admin 자격증명으로, 혹은 다른 role로 같은
   객체를 쓰는 것은 여전히 가능하고(그 principal에는 위 lock row Deny도 걸리지
   않는다), mgmt 리소스 자체의 변경도 막지 않는다. 구체적인 우회 경로가 바로 옆에
   하나 있었다: 이 PR이 삭제하고 외부 repo가 superset으로 계속 소유하는 `ci_runner`
   role은 `AmazonS3FullAccess`(+`ReadOnlyAccess`)가 attach된 채 runner SA 10개에 pod
   identity로 묶여 있어서, mgmt 클러스터의 CI 워크로드 pod가 이 state 버킷 전체를
   read/write할 수 있었다 — shared state의 Aurora/DocumentDB master password 평문 포함.
   runner pod는 PR 코드를 실행하므로 이건 이론적 경로가 아니다.

   그래서 이 PR에서 **버킷 정책으로 승격한다**(`terraform/global/terraform-state`,
   `state_custody_denials`). resource policy의 명시적 Deny는 어떤 identity policy의
   Allow보다도 우선하므로, managed FullAccess를 달아도 더 이상 권한이 생기지 않는다 —
   문서 경고와 이것의 차이가 정확히 그 지점이고, 그래서 이관과 같은 변경에 들어간다.
   해당 버킷에는 정책이 없었다(`NoSuchBucketPolicy` 실측). 범위는 이 repo가 소유한 state
   key들 + `global/*`이고, `ci_runner` 자기 레이어의 key는 뺀다 — 저쪽이 소유하고 apply
   한다. TLS 강제 Deny도 같이 건다.

   `NotPrincipal`은 쓰지 않는다: assumed-role 세션 ARN과 role ARN이 달라 예외 목록이
   조용히 fail-open된다. principal을 직접 지정하면 실수는 fail-closed(그 role이 접근을
   잃는다) 쪽으로 떨어진다. 남는 한계: 이건 계정 내 특정 role 대상이므로, admin
   자격증명을 든 사람은 여전히 쓸 수 있다. 외부 repo에서 그 managed policy 자체를
   축소하는 것은 저쪽 repo의 변경이라 여기 범위가 아니다.

### 이 ADR이 닫지 않는 것 (blocking follow-up)

이관 자체와 분리해 추적한다. 둘 다 "문서 경고는 통제가 아니다"라는 이 ADR 자신의
원칙에 걸리는 항목이므로, 후속으로 남긴다는 사실을 여기 명시한다.

1. **외부 repo의 `AmazonS3FullAccess` 축소.** 버킷 정책 승격은 이 PR에서 했으므로
   (Decision 5) `ci_runner`가 이 repo의 state에 닿는 경로는 닫혔다. 남은 것은 그 role이
   *애초에* 버킷 전체 권한을 들고 있을 이유가 없다는 것 — 그건
   `AWS-Demo-Platform/infra/eks-mgmt`의 변경이라 이 repo에서 할 수 없다. 저쪽에
   요청으로 추적한다(`iam:PassRole role/*`, `bedrock-agentcore:*`도 같은 대상).
2. **stale mgmt SG 감지.** mgmt를 replace하면 ArgoCD → spoke 접근이 조용히 끊기고
   다음 sync 실패까지 드러나지 않는다. 인시던트 중에는 그 sync가 롤백 채널이다.
   spoke의 `terraform plan -detailed-exitcode`가 신호를 내지만(SG를 live로 조회하므로
   교체가 ingress 규칙 diff로 보인다) 정기 실행이 없다. ArgoCD hub의 spoke connection
   알람 또는 예약된 drift plan 중 하나가 필요하다. `scripts/check-mgmt-guards.sh`가
   수동 실행으로 그 확인을 한 명령으로 만들었지만(가드 상태 + 두 spoke 수렴 +
   `argocd cluster list` 도달성), 정기 실행은 아니라 여전히 사람이 돌려야 한다.
   상시 감지는 이 repo에 프로덕션 대상 스케줄 자동화를 새로 들이는 일이라 별도 결정으로
   분리한다.

## Consequences

**얻는 것**

- state 객체당 writer 1명. CI 경로(= `github-actions-role`)에서는 동시 apply로 state가
  깨질 경로가 IAM으로 차단된다. 사람의 admin 세션은 관례로만 막힌다.
- cross-repo state 스키마 의존 제거. mgmt 레이어 리팩터링이 이 repo를 깨뜨리지 않는다.
- 이름 스쿼팅으로 trust boundary를 넘는 경로가 VPC assert로 막힌다. 태그 assert는
  보조 신호에 가깝다 — 태그는 클러스터를 만드는 주체가 임의로 설정할 수 있으므로,
  실질 통제는 VPC 하나이고 태그는 "우리 플랫폼이 만든 것처럼 보이는지"까지만 본다.

**잃는 것 / 새로 관리해야 하는 것**

- **plan이 mgmt live 존재에 결합된다.** mgmt가 삭제·장애 상태거나
  `eks:DescribeCluster`가 실패하면, 트래픽을 받는 workload 클러스터의 모든 Terraform
  작업이 막힌다. Break-glass는 **3 apply**다: `shared/terraform.tfvars`에
  `mgmt_cluster_security_group_id_override`를 커밋해 `shared/` apply → `eks-az-a` apply
  → `eks-az-c` apply (Decision 4). spoke root에는 그 이름의 변수가 없으므로
  `-var mgmt_cluster_security_group_id=...`를 spoke에 주면 즉시 에러다 — 값은 `shared/`가
  단일 소스이고 spoke는 remote state로 읽는다. 빈 문자열을 주면 EKS 모듈이 해당 ingress
  규칙을 아예 만들지 않는다
  (`count = var.argocd_security_group_id != "" ? 1 : 0`). 워크로드 트래픽 경로
  (CloudFront → NLB → api-gateway)는 이 SG와 무관하므로 영향받지 않는다 — 끊기는 것은
  GitOps sync뿐이다. 실행 명령은 region README의 Runbooks가 정본이고, 복구 후
  `scripts/check-mgmt-guards.sh`로 가드 복구와 두 spoke 수렴을 확인한다.

  주의: break-glass 값이 foundation 레이어(`shared/`)에 있으므로 그 apply가 Aurora·
  DocumentDB·MSK를 포함한 레이어를 통과한다 — ArgoCD ingress 규칙 하나를 위한 blast
  radius로는 불균형하다. 그럼에도 여기 두는 이유는 spoke별 변수의 실패 양식(한쪽만
  해제)이 더 나쁘기 때문이고, 인시던트 중에는 `-target=module.mgmt_trust`가 아니라
  `shared/`의 plan을 읽고 변경이 output 하나뿐임을 확인한 뒤 apply하는 것이 절차다.

- **mgmt 이름 변경이 2단계 절차가 된다.** `mgmt_cluster_name`과
  `describable_cluster_names`가 같은 클러스터를 지칭한다 — 둘 다 이제 `shared/`에
  있으므로 한 파일이지만, 여전히 순서가 있다: 새 이름을 `shared/`에 추가해 apply하지
  않으면 spoke는 postcondition에 도달하기 전에 `AccessDenied`로 죽는다.

- **cold rebuild의 임계 경로에 외부 repo가 들어온다.** 정상 순서는
  `shared/` → mgmt(external) → `eks-az-{a,c}`다. mgmt는 shared state를 읽고
  spoke는 mgmt를 plan 시점에 조회하므로, 리전 전체를 처음부터 세우거나 복구하는
  시나리오에서 RTO에 `AWS-Demo-Platform` apply 시간이 그대로 더해진다. 정상
  운영 중에는 spoke plan의 선행조건일 뿐이다.

- **mgmt 재생성 시 spoke ingress가 stale해진다.** mgmt 클러스터를 replace하면
  EKS-managed SG ID가 바뀌고, 두 spoke를 재-apply하기 전까지 ArgoCD → spoke API 접근이
  조용히 끊긴다(워크로드는 계속 동작하므로 다음 sync 실패로만 드러난다). 절차는
  region README의 Runbooks 참조 — 요약하면 mgmt apply → 이 repo에서 spoke 2개
  (`eks-az-a`, `eks-az-c`) apply → mgmt에서 `argocd cluster list`로 두 spoke 연결 확인.

- **shared layer의 output 일부가 외부 계약이 된다.** `AWS-Demo-Platform`의 mgmt 레이어가
  이 repo의 shared state를 읽는다: `vpc_id`, `private_subnet_ids`,
  `alb_security_group_id`, `nlb_security_group_id`,
  `internal_observability_nlb_security_group_id`, `kms_key_arns["s3"]`.
  이 이름·타입은 breaking change 금지 대상이다. ALB/NLB SG 두 개는 놓치기 쉽다 —
  삭제된 `eks-mgmt/main.tf`의 `module "eks"` 인자였고 이 repo 안에는 그것을 읽는
  코드가 남지 않기 때문이다. 외부 repo가 superset이므로 이 목록은 상한이 아니라
  하한으로 취급해야 한다.

- **이 repo가 더 이상 만들지 않는 것 전체 목록.** 삭제된 `eks-mgmt/` 레이어가 소유했던
  리소스는 이제 전부 `AWS-Demo-Platform`이 만든다:
  `module "eks"`, `module "alb"`, `module "otel_collector_irsa"`,
  `module "tempo_storage"`(mgmt 중앙 Tempo S3 + IRSA),
  `aws_iam_role.ci_runner` + inline 정책 5개(`ci_runner_ecr`, `ci_runner_bedrock`,
  `ci_runner_cloudfront`, `ci_runner_ecs`, `ci_runner_cdk_deploy`) + managed policy
  attachment 2개(`ReadOnlyAccess`, `AmazonS3FullAccess`),
  그리고 `aws_eks_pod_identity_association.ci_runner` 10개(runner SA당 1개).
  workload 클러스터의 per-AZ `tempo_storage`/`otel_collector_irsa`/`alb`는 이 repo에 남는다.
  `AWS-Demo-Platform`의 `infra/eks-mgmt`는 이 집합의 superset이다(추가로
  `ci_runner_ami_build`를 가진다) — 그래서 이관에 destroy가 없다.

- **곁가지로 고친 것 하나.** `terraform_lock_table` 모듈 default가 단수형
  `multi-region-mall-terraform-lock`이었고, 실제 테이블과 전 레이어 `backend.tf`는
  복수형 `-locks`다. CI의 DynamoDB grant가 존재하지 않는 테이블을 가리키고 있었다는
  뜻이다 — 이 PR이 IAM 정책을 건드리는 김에 같이 고쳤다. 이 ADR의 결정과는 무관한
  오타 수정이다.

- **`expected_mgmt_vpc_id`로 다른 VPC를 허용하는 것은 VPC peering 전제다.** SG를
  ingress source로 참조하는 것은 peering된 VPC 사이에서만 되고 Transit Gateway를
  넘지 못한다. mgmt가 TGW로만 연결된 VPC로 옮겨가면 이 변수로 가드를 풀어도 규칙이
  동작하지 않는다 — 그때는 CIDR 기반 규칙으로 전환해야 한다.

## References

- `AWS-Demo-Platform` `ed97945` (코드 이관), `122196a` (단독 소유 선언, 2026-06-24)
- `terraform/environments/production/ap-northeast-2/README.md` — 레이어 표, apply 순서,
  Runbooks(break-glass·재생성 절차의 정본)
- `terraform/modules/security/iam/github-actions.tf` — `describable_cluster_names`,
  `externally_owned_state_keys`의 Allow/Deny 문장
- `terraform/modules/security/iam/variables.tf` — 위 두 변수와 `terraform_lock_table`
  선언
- `terraform/modules/security/mgmt-cluster-trust/` — live lookup, postcondition
  4개(+override 경로 2개), `check`/`released_guards`. 양 spoke가 공용으로 호출한다
- `terraform/environments/production/ap-northeast-2/eks-az-a/main.tf`,
  `terraform/environments/production/ap-northeast-2/eks-az-c/main.tf` — 위 모듈 호출
- `terraform/environments/production/ap-northeast-2/shared/variables.tf` —
  `mgmt_cluster_security_group_id_override`(break-glass 단일 소스)
- `terraform/environments/production/ap-northeast-2/shared/main.tf` — `module "iam"` 호출

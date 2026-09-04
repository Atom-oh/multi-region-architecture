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
     표기 주의(한 값에 표기가 두 가지다): `shared/`의 변수와 output은
     `mgmt_cluster_security_group_id_override`(`_override` 접미사)이고, 모듈 변수와
     guard label은 접미사 없는 `mgmt_cluster_security_group_id`다 — tfvars에 적는
     이름은 전자다.
     non-null이면 data source의 `count`가 0이 되어 **cluster read 자체와
     postcondition 전체가 사라진다.** 대신 값이 빈 문자열이 아니면
     `data "aws_security_group" "mgmt_override"`가 그 SG를 조회해 shared VPC 소속인지
     assert한다. 비교 대상은 `var.shared_vpc_id`다(round-9 review MAJOR 수정 —
     이전에는 `local.expected_mgmt_vpc_id`였다). `expected_mgmt_vpc_id`와 이 override는
     둘 다 `shared/`에 살고 둘 다 각자의 `TF_VAR_*`로 독립적으로 해제 가능한 별개의
     trust 입력인데, override를 *해제 가능한* `expected_mgmt_vpc_id`에 앵커하면
     `shared/` 한 번의 변경(`expected_mgmt_vpc_id`만 넓히기)으로 override 경로의
     VPC assert까지 같이 넓어졌다 — 하나의 값 해제가 두 가드를 동시에 무력화하는
     구조였다. override는 인시던트 중 사람이 수동으로 지정하는 임시값이지 영구
     relocation 선언이 아니므로, `expected_mgmt_vpc_id`가 해제돼 있어도 이 region의
     실제 shared VPC로 고정한다. 정당한 영구 relocation은 여전히 live-lookup
     경로(`expected_mgmt_vpc_id`를 존중하는)로 처리한다 — 이건 override 경로가
     받아들이는 값만 바꾼다. 여기에 `kubernetes.io/cluster/<name>=owned`
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
     정상 plan과 똑같이 보이지 않게 한다. `check`와 output은 다섯 개 trust 입력 중
     네 개를 직접 본다 — `TF_VAR_expected_mgmt_tags='{}'`, `TF_VAR_expected_mgmt_vpc_id=vpc-...`,
     `TF_VAR_mgmt_cluster_name=...`도 같은 trust boundary를 넓히는데, override만
     감지하면 그 경로들의 plan은 정상 plan과 완전히 동일하게 보인다.
     `mgmt_cluster_name`이 목록에 있는 이유는 그것이 단순 레이블이 아니라 trust
     입력이기 때문이다 — override 경로가 SG의 `aws:eks:cluster-name`을 이 값과
     비교하므로, override와 name을 같이 넘기면 다른 클러스터의 SG가 통과한다.
     다섯 번째 입력 `default_mgmt_cluster_name`은 그 `mgmt_cluster_name` 비교의
     baseline 역할만 하고, **자기 자신의 drift를 감지하는 독립적인 가드는 없다** —
     round-9에서 한 번 시도했었다(baseline을 모듈에 하드코딩된 `"mall-apne2-mgmt"`
     리터럴과 비교해, 두 입력을 TF_VAR_* 두 개로 동시에 같은 새 이름으로 옮기는
     우회를 잡으려 했다). round-10 리뷰에서 그 시도 자체가 버그로 확인돼 제거했다:
     state만 보고는 "rename runbook을 절차대로(두 번의 apply로) 완료해 baseline이
     새 이름에 정당하게 도달한 것"과 "두 입력을 한 apply에서 같이 옮겨 name 가드를
     우회한 것"을 구분할 방법이 없다 — 둘의 최종 state가 완전히 동일하기 때문이다.
     그 결과 그 가드는 정당한 rename을 완료할 때마다 이후 영원히 "released"로
     보고했다("해제 신호가 노이즈가 되는 것을 막는다"는 이 가드 시스템 자신의
     목표와 정면으로 충돌). state 비교로는 원천적으로 풀 수 없는 문제라 판단해
     복구하기보다 제거했다 — 이 특정 우회(동시 변경)를 잡으려면 state가 아니라
     감사 기록(shared/ apply에 대한 CloudTrail, 또는 shared/tfvars 변경에 대한
     필수 리뷰 게이트)이 필요하다. output은 해제된 가드 목록을 state에 남겨 사후
     감사가 break-glass apply를 구분할 수 있게 한다. 단 이 output은 *현재* state의
     값이므로 이후 정상 apply가 빈 리스트로 덮어쓴다 — 지나간 break-glass를 되짚으려면
     state 버킷의 버저닝이나 CloudTrail이 필요하고, output 자체는 "지금 해제 상태인가"
     신호로 읽어야 한다(값은 bool이 아니라 해제된 가드 목록이다).
   - `var.break_glass_confirm` — escape hatch가 아니라 그 사용의 **acknowledgment
     gate**다(기본값 `false`, trust 입력 아님 — 누가 신뢰되는지를 바꾸지 않으므로
     released_guards에는 없다). override가 non-null인데 이것이 true가 아니면
     `terraform_data.break_glass_gate`의 precondition이 plan을 hard fail시킨다 —
     `shared/` root와 모듈 양쪽에 동일하게 있어, override를 선언하는 `shared/`
     plan부터 막힌다. override와 같은 `shared/terraform.tfvars` 변경에 함께
     넣는다. 복구 후 override를 unset하며 이것만 true로 남기면 다음 override가
     gate 없이 통과하므로, `scripts/check-mgmt-guards.sh`가 "confirm true인데
     override unset"을 FAIL로 낸다.
   - `var.mgmt_cluster_name` — 이름 변경 대응. `shared/`의 `describable_cluster_names`는
     이 변수에서 파생된다(`[var.mgmt_cluster_name]`, round-9 review MAJOR 수정 — 이전에는
     별도 리터럴이라 `mgmt_cluster_name`과 독립적으로 drift할 수 있었다), 그래서 이름
     변경은 `shared/` 한 번의 apply로 이름 output과 IAM grant가 함께 바뀐다(아래
     Consequences). 이 변수는 위 `check`/output의 감시 대상이기도 하다.

   가드 전체(`data` 2개, postcondition 6개, `check`, `released_guards`, 그리고
   plan-time hard fail인 `terraform_data.break_glass_gate` — 동일 precondition이
   `shared/` root에도 복제되어 override를 선언하는 그 layer의 plan부터 막는다)는
   `terraform/modules/security/mgmt-cluster-trust`에 두고 양 spoke가 호출한다. 두 spoke가
   문자 단위로 같은 로직을 필요로 하는데, 복제해두면 한쪽만 수정되는 drift가 리뷰에서
   보이지 않는다 — API server에 누가 닿을 수 있는지를 정하는 코드에는 맞지 않는 실패
   양식이다.

   trust 입력 **다섯 개 전부**(`mgmt_cluster_name`, `default_mgmt_cluster_name`,
   `expected_mgmt_vpc_id`, `expected_mgmt_tags`, break-glass override)가 spoke
   변수가 아니라 `shared/`의 변수이고, spoke는 그것을 remote state output으로 읽는다.
   `default_mgmt_cluster_name`은 round-8에서 추가된 다섯 번째 입력이다 — `check`의
   released_guards 비교 기준(baseline) 자체다. 단 이 변수 **자신의** drift를 감시하는
   released_guards 항목은 없다: round-9에서 추가했다가 round-10에서 제거했다(위
   released_guards 설명 참조 — 정당한 rename 완료 후의 state와 우회의 state를 구분할
   수 없어 모든 정상 rename을 영구 "released"로 오보했다). 대신 shared↔spoke의
   `mgmt_trust_fingerprint` 비교(`scripts/check-mgmt-guards.sh`)가 이 값의 미수렴
   창을 다른 네 입력과 함께 잡는다. spoke별 변수면 한쪽만
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
   key들 + `global/*` + `ci_runner` 자기 레이어(`eks-mgmt`)의 key다. **자기 레이어
   key도 뺴지 않고 Deny한다**(round-10 리뷰 MAJOR 수정 — 이전에는 "저쪽이 소유하고
   apply한다"는 근거로 뺐다. 그런데 ADR 자신의 서술대로 `ci_runner`는 PR 코드를
   실행하는 self-hosted runner role이고, `infra/eks-mgmt`를 실제로 apply하는 건
   그쪽의 Atlantis — 별개 identity다. repo 소유권과 이 role 자신의 권한 필요성은
   별개이고, `ci_runner`가 자기 레이어의 state를 읽거나 쓸 정당한 이유도 없다 — 그
   key 하나를 열어두는 것은 이 버킷 정책 전체가 막으려는 "state 객체당 writer
   2명 이상" 위험을 범위만 좁혀 그대로 남겨두는 것이었다). TLS 강제 Deny도 같이 건다.

   `NotPrincipal`은 쓰지 않는다: assumed-role 세션 ARN과 role ARN이 달라 예외 목록이
   조용히 fail-open된다. 대신 `Principal = "*"` + `aws:PrincipalArn` 조건절에 차단
   대상 role ARN을 직접 나열한다(Principal 필드 자체에 role ARN을 넣는 것과는 다르다 —
   그 방식의 문제는 아래 round-8 수정에서 다룬다). 단, 이 나열 방식의 실패 양식은
   정확히 알아둘 것(round-12 리뷰 M3-2, 확인됨): `Principal="*"` + Deny 조건절에서
   ARN을 잘못 적으면 그 Deny는 **아무에게도 적용되지 않고** `PutBucketPolicy`는
   성공한다 — 신호 없는 fail-open이다. 목록에 없는 principal(신규 role, admin 세션,
   `ci_runner`가 자기 `sts:AssumeRole`/`iam:PassRole` 권한으로 pivot한 세션) 전체에
   대해서도 마찬가지로 열려 있다. 즉 이 denylist는 나열된 role의 직접 호출 경로에
   대한 표적 완화이지 custody boundary가 아니다(아래 "이 ADR이 닫지 않는 것" 1 —
   allowlist 전환 — 이 그 boundary가 되는 경로다). 남는 한계: 이건 계정 내 특정 role 대상이므로, admin
   자격증명을 든 사람은 여전히 쓸 수 있다. 외부 repo에서 그 managed policy 자체를
   축소하는 것은 저쪽 repo의 변경이라 여기 범위가 아니다.

   객체 키에 건 Deny 하나만으로는 닫히지 않는 경로가 있었다: `ci_runner`가 든
   `AmazonS3FullAccess`는 버킷 ARN 자체에 대한 `s3:PutBucketPolicy`/
   `DeleteBucketPolicy`도 허용하므로, 그 role이 이 정책 문서 자체를 덮어쓰거나 지운
   뒤 원래 막혀 있던 객체를 읽을 수 있었다 — object-level Deny는 정책 문서를 보호하지
   않는다. 그래서 같은 `state_custody_denials` 순회에서 버킷 ARN 대상으로
   `PutBucketPolicy`/`DeleteBucketPolicy`/`PutBucketAcl`/`PutBucketPublicAccessBlock`/
   `PutLifecycleConfiguration`/`PutBucketVersioning`/`PutReplicationConfiguration`도
   같은 principal에 Deny한다. 이 저장소 자신의 apply 경로(각 레이어를 소유한
   principal)는 객체 읽기/쓰기만 하고 버킷 정책 자체를 바꾸지 않으므로 영향 없다.

   **round-8 수정(CRITICAL): Principal을 role ARN 직접 지정 대신 `"*"` +
   `aws:PrincipalArn` 조건으로 바꿨다.** `Principal = { AWS = "arn:...:role/name" }`
   는 정책 저장 시점에 AWS 가 그 role 의 **고유 내부 principal ID** 로 고착시킨다.
   `mall-apne2-mgmt-ci-runner` 는 외부 repo(`AWS-Demo-Platform`)가 소유·재생성할 수
   있는 role 이므로, 저쪽의 통상적인 role 재생성(공격이 아니라 유지보수) 한 번으로
   새 role 은 새 principal ID 를 받고 이 Deny 는 더 이상 매치하지 않는다 — custody
   가 아무 신호 없이 조용히 다시 열린다. `aws:PrincipalArn` 은 assumed-role 세션의
   role ARN 을 요청 시점에 평가하므로, role 재생성 전후로 같은 ARN 을 유지해 이
   정책이 막으려는 바로 그 사건을 넘어 fail-closed 상태를 지킨다. 부수 효과로
   cold-bootstrap 문제도 해결된다: role ARN Principal 은 그 role 이 아직 없으면
   `PutBucketPolicy` 자체가 "Invalid principal" 로 실패했다.

   **round-8 수정(MAJOR): `check-mgmt-guards.sh` 의 argocd 도달성 검사가 여전히
   fail-open 이었다.** `argocd cluster list ... || true` 가 명령 실패(인증 만료
   등)를 빈 문자열로 흡수한 뒤, 그 흡수된 빈 문자열을 `[ -n "$ARGO_RAW" ]` 로만
   검사해 **검증 루프 전체를 건너뛰었다** — "CLI 부재/명령 실패/Unknown 전부 FAIL"
   이라는 주석의 주장과 실제 코드가 반대였다. 이제 `argocd cluster list` 의 종료
   코드를 직접 검사해 명령 실패를 그 자리에서 즉시 FAIL 로 잡고, 검증 루프는 조건
   없이 항상 돈다.

   **round-8 수정(MAJOR): `env:/` workspace 경로가 세 곳(identity policy Deny,
   버킷 정책 Deny, DynamoDB LeadingKeys) 모두에서 빠져 있었다.** `${key}` /
   `${key}*` / `${dirname(key)}/*` 세 패턴은 모두 키 자신의 prefix 에 앵커하는데,
   TF workspace 의 state 객체는 버킷 **루트**의 `env:/<name>/<key>` prefix 아래에
   있어 어느 패턴에도 매칭되지 않는다. 세 곳 모두에 `env:/*/<key>` 계열 리소스를
   추가해, workspace 를 만들어 같은 mgmt 리소스에 두 번째 writer 가 되는 경로를
   닫았다.

   **round-8 수정(MAJOR): 정당한 mgmt rename 후 name 가드가 영구 해제 상태로
   남았다.** `released_guards` 는 `mgmt_cluster_name` 을 모듈에 하드코딩된
   `default_mgmt_cluster_name`(항상 `"mall-apne2-mgmt"`)과 비교하는데, 이 baseline
   은 spoke 어디서도 override 하지 않아 절대 바뀌지 않았다. rename runbook 을
   정상적으로 완료해도(양쪽 spoke 가 새 이름에 수렴해도) guard 는 계속 "released"
   로 남고 `check-mgmt-guards.sh` 는 그 이후 영원히 실패한다 — "해제 신호가
   노이즈가 되는 것을 막는다"는 이 가드 시스템 자신의 목표와 충돌한다.
   `default_mgmt_cluster_name` 을 `shared/` 의 신규 변수/output 으로 단일소싱하고,
   rename runbook 의 마지막 단계로 이 baseline 갱신을 추가했다(양쪽 spoke 가 새
   이름에 완전히 수렴한 **뒤에만** — 순서를 뒤집으면 아직 옮기지 않은 spoke 가
   반대로 released 처럼 보인다).

### 이 ADR이 닫지 않는 것 (blocking follow-up)

이관 자체와 분리해 추적한다. 둘 다 "문서 경고는 통제가 아니다"라는 이 ADR 자신의
원칙에 걸리는 항목이므로, 후속으로 남긴다는 사실을 여기 명시한다.

1. **외부 repo의 `AmazonS3FullAccess` 축소 — 그리고 role-pivot으로 우회 가능하다는 점을
   명시.** 버킷 정책 승격(Decision 5)은 `ci_runner`가 **자기 자신의 principal ARN으로**
   이 state에 닿는 경로만 닫는다. 그 role은 (외부 repo가 소유·유지하는) 삭제된
   `eks-mgmt/main.tf`에 보이는 인라인 정책으로 `sts:AssumeRole` on `role/cdk-*`와
   `iam:PassRole` on `role/*`(조건: `ecs-tasks.amazonaws.com`) + `ecs:RunTask`/
   `RegisterTaskDefinition`(`Resource = "*"`)를 갖고 있다 — 즉 이 role은 **다른
   principal ARN이 되는 경로를 최소 두 개** 가진다: (a) `cdk-hnb659fds-deploy-role-*`로
   `AssumeRole`, (b) 계정 내 임의 role을 ECS task role로 `PassRole`한 뒤 그 role로
   `RunTask`. `aws:PrincipalArn` 조건은 요청 시점의 principal ARN을 평가하므로, 새
   principal ARN이 되는 이 두 경로에는 버킷 정책의 Deny가 **매치하지 않는다** — 즉
   "`ci_runner`의 state 접근 경로가 닫혔다"는 것은 *그 role 자신의 ARN으로 직접
   호출하는 경로*에만 참이고, 이 pivot 경로는 이 PR로 닫히지 않았다. 두 pivot 모두
   외부 repo(`AWS-Demo-Platform/infra/eks-mgmt`)가 소유한 `ci_runner`의 권한 범위이므로
   이 repo에서 고칠 수 없다 — 저쪽에 다음을 요청으로 추적한다: `AmazonS3FullAccess`
   제거, `iam:PassRole`을 `role/*agentcore*`처럼 실제로 필요한 role로 좁히기(현재
   `role/*` — 임의 role pivot의 근원), `sts:AssumeRole`을 `cdk-*` 중 실제 필요한
   role ARN으로 좁히기, `ecs:RunTask`/`RegisterTaskDefinition`의 `Resource`를 `"*"`
   대신 이 클러스터가 실제로 실행하는 task definition ARN으로 좁히기. 이 pivot이
   막히기 전까지는 버킷 custody를 "완전히 닫힘"이 아니라 "principal ARN 직접 호출을
   막는 부분 완화"로 취급할 것.
2. **stale mgmt SG 감지.** mgmt를 replace하면 ArgoCD → spoke 접근이 조용히 끊기고
   다음 sync 실패까지 드러나지 않는다. 인시던트 중에는 그 sync가 롤백 채널이다.
   spoke의 `terraform plan -detailed-exitcode`가 신호를 내지만(SG를 live로 조회하므로
   교체가 ingress 규칙 diff로 보인다) 정기 실행이 없다. ArgoCD hub의 spoke connection
   알람 또는 예약된 drift plan 중 하나가 필요하다. `scripts/check-mgmt-guards.sh`가
   수동 실행으로 그 확인을 한 명령으로 만들었지만(가드 상태 + 두 spoke 수렴 +
   `argocd cluster list` 도달성, round-9에서 shared/ 의 현재 값과의 3자 비교도
   추가됐다), 정기 실행은 아니라 여전히 사람이 돌려야 한다.
   상시 감지는 이 repo에 프로덕션 대상 스케줄 자동화를 새로 들이는 일이라 별도 결정으로
   분리한다.
3. **수렴 창(convergence window)에서의 split-schema write.** (round-9 review L4,
   4개 독립 모델 확인) mgmt replace 또는 break-glass 후 두 spoke 중 하나만
   재apply되면, 그 사이 창에서 weighted NLB는 여전히 두 spoke 모두에 트래픽을
   보내면서 ArgoCD는 한쪽에만 도달한다 — 스키마 마이그레이션을 포함한 GitOps
   변경이 fleet의 절반에만 반영된 채로 같은 Aurora/DocumentDB primary에 신구
   스키마가 동시에 write할 수 있다. 이 ADR이 도입한 통제(single-sourcing,
   `check-mgmt-guards.sh`)는 그 창을 사후에 **감지**하지만 사전에 **막지는**
   않는다 — 감지는 사람이 수동으로 스크립트를 돌려야 하는 시점에만 일어난다.
   실질적인 예방에는 (a) 두 spoke의 ArgoCD revision이 갈리면 스키마 마이그레이션을
   포함한 Application의 auto-sync를 막는 게이트, 또는 (b) 한쪽 spoke의 sync가
   실패한 상태로 감지되면 그 spoke의 NLB target weight를 0으로 내리는 자동 경로가
   필요하다. 둘 다 이 repo가 아직 갖지 않은 기능(ArgoCD Application 상태를 읽어
   NLB 가중치를 바꾸는 자동화, 또는 revision-parity 게이트)이라 별도 설계·구현이
   필요한 후속 작업으로 남긴다. expand-contract 방식의 스키마 마이그레이션 정책
   문서화도 같은 후속에 포함한다.
4. **신뢰 대상이 "ArgoCD"가 아니라 mgmt 클러스터 SG 전체.** (round-9 review L3,
   확인됨) `argocd_security_group_id`에 들어가는 값은 EKS가 관리하는 **cluster SG**로
   mgmt의 모든 노드에 붙는다 — 같은 mgmt 클러스터가 PR 코드를 실행하는 self-hosted
   runner pod 10개도 호스팅하므로, workload API server의 네트워크 계층 ingress
   trust 대상은 "ArgoCD"가 아니라 "mgmt 클러스터 전체"다. k8s RBAC가 남아 있어
   즉시 침해는 아니지만, 통제로서는 의도보다 넓다. 실질적인 축소에는 mgmt 쪽에서
   ArgoCD 전용 SG(또는 pod 단위 SG)를 만들어 그 output만 노출하는 변경이 필요한데,
   그건 `AWS-Demo-Platform/infra/eks-mgmt`의 변경이라 이 repo에서 할 수 없다 —
   저쪽에 새 output 하나를 요청으로 추적한다.
5. **trust 입력 해제에 preventive 통제가 없다 — 단, override 하나는 이제 예외.**
   (round-11에서 부분 해소) 다섯 개 trust 입력 모두 `TF_VAR_*`로 해제 가능하고
   `check` 블록은 정의상 plan을 실패시키지 않으므로, 프로덕션 API server ingress
   source를 정하는 값 대부분에는 사람이 수동으로 돌리는
   `scripts/check-mgmt-guards.sh` 외의 게이트가 없다. `mgmt_cluster_security_group_id_override`
   만은 이제 예외다 — `break_glass_confirm` 변수와 `mgmt-cluster-trust` 모듈의
   `terraform_data.break_glass_gate` `precondition`으로 실제 plan-time hard
   fail을 건다(review M7 제안, 조건 없이 선언된 `terraform_data`라 override 값이
   `sg-...`든 `""`든 항상 평가된다 — 두 `data` 블록에 걸었다면 override가 `""`일 때
   양쪽 모두 `count=0`이라 이 가드 자체가 평가되지 않았을 것). 나머지 네 입력
   (`mgmt_cluster_name`, `default_mgmt_cluster_name`, `expected_mgmt_vpc_id`,
   `expected_mgmt_tags`)에는 여전히 이런 게이트가 없다 — CI 없이도 가능한 개선
   (plan JSON에 대한 OPA/Conftest 검사, 또는 이들에도 비슷한 확인 변수)은 후속으로
   남긴다.

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
  `mgmt_cluster_security_group_id_override`와 `break_glass_confirm = true`를 **같은
  변경으로** 커밋해 `shared/` apply → `eks-az-a` apply
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
  `shared/`의 plan을 읽고 바뀌는 것이 정확히 output 네 개 —
  `mgmt_cluster_security_group_id_override_set`(false→true),
  `mgmt_cluster_security_group_id_override_value`(""→값),
  `break_glass_confirm`(false→true), `mgmt_trust_fingerprint`(재계산) — 뿐임을
  확인한 뒤 apply하는 것이 절차다(개수만 세지 말고 이름을 대조할 것 — 이 확인이
  Aurora/DocumentDB/MSK를 포함한 layer의 blast radius 통제다).

- **mgmt 이름 변경은 2단계 절차다.** `describable_cluster_names`는
  `mgmt_cluster_name`에서 파생되므로(`[var.mgmt_cluster_name]`) 이름 output과
  `eks:DescribeCluster` IAM grant는 이제 `shared/` 한 번의 apply로 함께 바뀐다 — 둘이
  독립적으로 drift할 수 없다(round-9 review MAJOR 수정, 이전에는
  `describable_cluster_names`가 별도 리터럴이었다). 남는 두 단계는 순서가 있는
  이유가 다르다: (1) `shared/`에서 `mgmt_cluster_name`을 새 이름으로 바꿔 apply하고
  양 spoke를 apply — 이 시점부터 두 spoke는 새 이름을 신뢰하지만
  `mgmt_cluster_name != default_mgmt_cluster_name`이라 released_guards가
  "released"를 보고한다(의도된 것 — rename 진행 중 신호. `check-mgmt-guards.sh`는
  이 단계에서 `--expect-released=mgmt_cluster_name`으로 실행할 것 — plain 모드는
  released guard가 있으면 그 이유를 안 따지고 FAIL한다. break-glass 런북의
  `--expect-released=mgmt_cluster_security_group_id`와 접두사가 다른 이유는
  round-11 리뷰 M6: 인자 없는 `--expect-released`는 released 가드 전부와 argocd
  미도달을 무조건 INFO로 낮췄는데, rename 중에는 mgmt가 살아 있는 게 전제라 argocd
  미도달을 노이즈로 볼 수 없고, break-glass 중에는 override 외의 가드가 같이
  released 돼도 안 된다 — 두 런북이 서로 다른 "무엇이 released 여도 되는지"를
  가지므로 접두사로 명시한다). (2) 양 spoke가 새 이름에 완전히 수렴한
  **뒤에만** `shared/`에서 `default_mgmt_cluster_name`을 같은 새 이름으로 바꿔
  apply하고 양 spoke를 다시 apply — 이제 baseline이 새 이름과 일치해
  released_guards가 다시 빈 목록이 된다. 순서를 뒤집으면(두 변수를 같은 apply에서
  같이 옮기면) 아직 옮기지 않은 spoke가 오히려 "engaged"로 잘못 보이는데, 이를
  잡는 자동 가드는 없다 — state만으로는 "두 apply로 절차대로 도달"과 "한 apply로
  동시에 옮김"을 구분할 수 없어서 시도했던 가드(round-9)를 round-10에서 제거했다
  (위 Decision 4·released_guards 설명 참조). "두 spoke가 실제로 수렴했는지"는
  운영자가 절차를 지켜 확인해야 하는 전제이지, 툴링이 강제해주지 않는다. 상세
  절차는 region README의 Runbooks가 정본이다.

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
  4개(+override 경로 2개), `check`/`released_guards`,
  `terraform_data.break_glass_gate`, `mgmt_trust_fingerprint`/`break_glass_confirm_engaged`
  output. 양 spoke가 공용으로 호출한다
- `terraform/environments/production/ap-northeast-2/eks-az-a/main.tf`,
  `terraform/environments/production/ap-northeast-2/eks-az-c/main.tf` — 위 모듈 호출
- `terraform/environments/production/ap-northeast-2/shared/variables.tf` —
  `mgmt_cluster_security_group_id_override`(break-glass 단일 소스)와
  `break_glass_confirm`(그 acknowledgment gate, `shared/` root와 모듈 양쪽의
  `terraform_data.break_glass_gate` precondition이 소비)
- `terraform/environments/production/ap-northeast-2/shared/main.tf` — `module "iam"` 호출

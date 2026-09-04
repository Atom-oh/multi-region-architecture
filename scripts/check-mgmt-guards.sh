#!/usr/bin/env bash
# mgmt 신뢰 경계 검사 — 두 spoke 가 (1) 가드를 다 걸고 있고 (2) 서로 수렴했고
# (3) shared/ 에 이미 적용된 값과도 수렴했는지 확인.
#
# 왜 스크립트인가: 모듈의 `check "mgmt_guards_engaged"` 는 plan 을 실패시키지 않는다
# (그게 check 블록의 정의다) — 가드가 해제된 plan 은 걸린 plan 과 출력이 다를 뿐,
# 종료 코드가 같다. 그래서 "가드 해제는 경고"라는 상태가 남는다. 이 스크립트가 그
# 경고를 종료 코드로 바꾼다: break-glass 후 복구 확인, 또는 apply 전 사전 점검용.
#
# 그리고 single-sourcing 은 두 spoke 가 *같은 값을 요구받는다*만 보장한다 — 각자
# apply 를 해야 실제로 반영되므로, 한쪽만 apply 된 창이 존재한다. 그 창은 값의 비교로만
# 잡히고, 이 스크립트가 그걸 한다. round-9 리뷰(L4 MAJOR, 확인됨): 두 spoke 를 서로
# 비교하는 것만으로는 "shared/ 에 이미 새 값이 apply 됐지만 두 spoke 모두 아직 재apply
# 하지 않은" 창을 놓친다 — 둘 다 여전히 옛 값에 수렴해 보여 PASS 가 나온다. shared/ 의
# *현재* 값과도 비교해야 그 창이 잡힌다(아래 3단계 비교).
#
# ponytail: 수동 실행. 스케줄러(cron/Actions)로 만들지 않는다 — 프로덕션에 무기한
# 도는 자동화를 리뷰 지적 하나로 새로 들이지 않는다는 게 이 저장소의 방침이고,
# stale-SG 상시 감지는 ADR-003 의 follow-up 으로 별도 추적된다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAYERS="$ROOT/terraform/environments/production/ap-northeast-2"
MGMT_REGION="ap-northeast-2"
FAIL=0

# --expect-released=<prefix1,prefix2,...>: 두 런북이 공유하는 모드 — break-glass
# 런북의 "3. 두 spoke 가 실제로 옮겨갔는지 검증" 단계, 그리고 rename 런북의 "1. 두
# spoke 가 새 이름에 수렴했는지 확인" 단계. 두 경우 다 특정 가드 하나가 released
# 상태인 것이 "정상"인데, plain 모드는 released guard 가 있으면 이유를 안 따지고
# FAIL한다 — 운영자가 "이 스크립트는 이 단계에서 항상 FAIL"이라고 학습해 종료 코드를
# 무시하게 된다(round-9 리뷰 L4 MAJOR).
#
# 인자 없는 `--expect-released`(round-9~10)는 released 인 가드 *전부*를 INFO로
# 낮췄다 — round-11 리뷰 M6, 확인됨: break-glass 런북이 override 하나만 기대하는데
# 그 사이 `TF_VAR_expected_mgmt_tags='{}'` 같은 무관한 가드가 같이 released 돼도
# 이 모드가 그것까지 조용히 삼켰다. 이제 어떤 가드가 released 여도 되는지 접두사로
# 명시해야 한다 — 그 접두사로 시작하지 *않는* released 항목은 여전히 FAIL이다.
# rename 런북(mgmt_cluster_name 하나만 기대)과 break-glass 런북(override 하나만
# 기대)이 서로 다른 접두사를 쓰므로 하드코딩할 수 없다.
EXPECT_RELEASED_PREFIXES=""
EXPECT_MGMT_DOWN=0
SELF_CHECK=0
usage() {
  echo "usage: $(basename "$0") [--expect-released=<comma-separated guard names>] [--mgmt-down] [--self-check]" >&2
  echo "  known guard names: mgmt_cluster_security_group_id mgmt_cluster_name expected_mgmt_vpc_id expected_mgmt_tags" >&2
  echo "  break-glass runbook step 3: --expect-released=mgmt_cluster_security_group_id --mgmt-down" >&2
  echo "  rename runbook step 1:      --expect-released=mgmt_cluster_name" >&2
  exit 2
}
# --expect-released 값은 실제 guard 이름만 받는다(round-12 리뷰 m4-3, 확인됨):
# 운영자가 방금 편집한 shared/ 변수명(mgmt_cluster_security_group_id_override)을
# 그대로 넣으면 매칭 실패로 released 항목이 전부 "기대 밖" FAIL이 됐다 — 결과는
# fail-closed지만 "이 단계는 항상 FAIL"이라는 학습을 만든다. `_override` 접미사는
# 정규화하고, 그 외 알 수 없는 이름은 조용히 아무것도 매칭하지 않는 대신 usage
# 에러로 즉시 거부한다.
KNOWN_GUARD_NAMES=" mgmt_cluster_security_group_id mgmt_cluster_name expected_mgmt_vpc_id expected_mgmt_tags "
for ARG in "$@"; do
  case "$ARG" in
    --expect-released=?*)
      RAW_LIST="${ARG#--expect-released=}"
      NORMALIZED=""
      OLD_IFS="$IFS"; IFS=','
      for NAME in $RAW_LIST; do
        NAME="${NAME%_override}"
        case "$KNOWN_GUARD_NAMES" in
          *" $NAME "*) NORMALIZED="${NORMALIZED:+$NORMALIZED,}$NAME" ;;
          *) IFS="$OLD_IFS"; echo "unknown guard name in --expect-released: '$NAME'" >&2; usage ;;
        esac
      done
      IFS="$OLD_IFS"
      EXPECT_RELEASED_PREFIXES="$NORMALIZED"
      ;;
    --mgmt-down) EXPECT_MGMT_DOWN=1 ;;
    --self-check) SELF_CHECK=1 ;;
    *) echo "unknown argument: '$ARG'" >&2; usage ;;
  esac
done
export EXPECT_RELEASED_PREFIXES

# argocd 도달 불가를 INFO로 낮추는 것은 --mgmt-down 을 명시했을 때만이다 —
# --expect-released=mgmt_cluster_security_group_id 에서 자동 유도하지 않는다
# (round-12 리뷰 M4-1, 확인됨): override 가 필요한 트리거 셋(mgmt 삭제 / 장애 /
# eks:DescribeCluster 실패) 중 세 번째는 mgmt 와 ArgoCD 가 멀쩡히 살아 있는
# 상황이라, 그때 argocd 미도달을 "예상됨"으로 삼키면 인시던트 중 롤백 채널이
# 실제로 끊긴 상태가 INFO 로 통과한다. mgmt 가 정말 죽어 있다고 아는 운영자만
# --mgmt-down 을 같이 명시한다. rename 은 mgmt 가 살아 있는 상태에서 진행하므로
# 이 플래그 없이 실행한다.

# --self-check: 판정 로직만 검증한다(AWS 접근 없음). 이 스크립트가 잡아야 하는 상태들 —
# 둘 다 깨끗함 / 한쪽 가드 해제 / guards 값 불일치 / SG 값 불일치 / 한쪽 미초기화 /
# argocd 미도달 / shared 에 이미 적용된 override·name 을 두 spoke 중 하나가 아직 못
# 집어간 상태 — 를 주입해 종료 코드가 실제로 갈리는지 확인한다. 가드 검사기 자체가
# 조용히 통과하는 것이 최악의 실패다.
#
# ARGOCD 픽스처는 실제 `argocd cluster list` 컬럼 형태(SERVER NAME VERSION STATUS ...)
# 로 맞춘다 — round-9 의 2컬럼(name-first) 합성 픽스처는 "이름이 두 번째 필드"라는
# 실제 CLI contract 위반을 구조적으로 잡을 수 없었다(round-10 리뷰 L4 MAJOR, 확인됨).
run_self_check() {
  _MGMT_SELF_CHECK=1 \
  MGMT_GUARDS_A="${1:-}" MGMT_GUARDS_C="${2:-}" \
  MGMT_SG_A="${3:-sg-mgmt}" MGMT_SG_C="${4:-sg-mgmt}" \
  MGMT_ARGOCD_STATUS="${5:-https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Successful
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Successful}" \
  MGMT_SHARED_NAME="${6:-mall-apne2-mgmt}" \
  MGMT_SHARED_OVERRIDE_SET="${7:-false}" MGMT_SHARED_OVERRIDE_VALUE="${8:-\"\"}" \
  MGMT_LIVE_SG="${9:-sg-mgmt}" \
  MGMT_SHARED_CONFIRM="${11:-false}" \
  MGMT_FP_A="${12:-\"fp\"}" MGMT_FP_C="${13:-\"fp\"}" MGMT_SHARED_FP="${14:-\"fp\"}" \
  bash "$0" ${10:-} >/dev/null 2>&1; echo $?
}
if [ "$SELF_CHECK" = "1" ]; then
  [ "$(run_self_check '[]' '[]')" = "0" ] || { echo "self-check FAILED: 둘 다 깨끗한데 PASS 아님"; exit 1; }
  [ "$(run_self_check '["x"]' '["x"]')" = "1" ] || { echo "self-check FAILED: 양쪽 가드 해제인데 FAIL 아님"; exit 1; }
  [ "$(run_self_check '[]' '["x"]')" = "1" ] || { echo "self-check FAILED: guards 불일치인데 FAIL 아님"; exit 1; }
  [ "$(run_self_check '[]' '[]' 'sg-old' 'sg-new')" = "1" ] || { echo "self-check FAILED: SG 불일치인데 FAIL 아님"; exit 1; }
  [ "$(run_self_check '' '[]')" = "1" ] || { echo "self-check FAILED: 한쪽 read 실패인데 FAIL 아님"; exit 1; }
  [ "$(run_self_check '[]' '[]' 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Successful
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Unknown')" = "1" ] || { echo "self-check FAILED: argocd 미도달인데 FAIL 아님"; exit 1; }
  # stale 등록 오탐 방지: "mall-apne2-az-a-old" 가 이름 필드(두 번째)에 있어도
  # "mall-apne2-az-a" 로 오매칭되면 안 된다 — 실제로는 두 az 모두 미등록으로 FAIL.
  [ "$(run_self_check '[]' '[]' 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a-old v1.30.0 Successful
https://mgmt-c.example:6443 mall-apne2-az-c-old v1.30.0 Successful')" = "1" ] || { echo "self-check FAILED: stale 등록(az-a-old)이 az-a 로 오매칭됨"; exit 1; }
  # 둘 다 [] 로 수렴해 보이지만 shared/ 에 이미 override 가 적용돼 있고 spoke 는 아직
  # 못 집어간 상태(3자 비교가 잡아야 하는 창).
  [ "$(run_self_check '[]' '[]' 'sg-mgmt' 'sg-mgmt' '' 'mall-apne2-mgmt' 'true' '"sg-newer"')" = "1" ] || { echo "self-check FAILED: shared override 미수렴인데 FAIL 아님"; exit 1; }
  # 같은 창을, override 가 아니라 live lookup 경로(이름 변경)로: shared 는 이미 새
  # 이름으로 렌더된 live SG 를 가리키는데 두 spoke 는 여전히 옛 SG 를 신뢰.
  [ "$(run_self_check '[]' '[]' 'sg-mgmt' 'sg-mgmt' '' 'mall-apne2-mgmt' 'false' '' 'sg-live-new')" = "1" ] || { echo "self-check FAILED: shared live SG 미수렴인데 FAIL 아님"; exit 1; }
  # --expect-released=mgmt_cluster_security_group_id (break-glass): 그 접두사의
  # released 항목 + argocd 미도달은 INFO 로 내려가지만 수렴 실패는 여전히 FAIL.
  OVERRIDE_GUARD='["mgmt_cluster_security_group_id=sg-mgmt (cluster lookup and its postconditions skipped)"]'
  [ "$(run_self_check "$OVERRIDE_GUARD" "$OVERRIDE_GUARD" 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Unknown
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Unknown' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=mgmt_cluster_security_group_id --mgmt-down')" = "0" ] || { echo "self-check FAILED: --expect-released=override 인데 released+argocd-미도달로 FAIL"; exit 1; }
  [ "$(run_self_check "$OVERRIDE_GUARD" '["mgmt_cluster_security_group_id=sg-other (cluster lookup and its postconditions skipped)"]' 'sg-mgmt' 'sg-mgmt' '' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=mgmt_cluster_security_group_id --mgmt-down')" = "1" ] || { echo "self-check FAILED: --expect-released 여도 guards 불일치는 FAIL 이어야 함"; exit 1; }
  # M6: 기대한 접두사 외의 가드가 *같이* released 되면, 기대 범위 안이어도 전체 FAIL —
  # break-glass가 override 만 기대하는데 무관한 가드(예: expected_mgmt_tags)까지
  # 조용히 삼키면 안 된다(round-11 리뷰 M6, 확인됨).
  MIXED_GUARDS='["mgmt_cluster_security_group_id=sg-mgmt (cluster lookup and its postconditions skipped)","expected_mgmt_tags={} (provisioning-tag guard widened or dropped)"]'
  [ "$(run_self_check "$MIXED_GUARDS" "$MIXED_GUARDS" 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Unknown
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Unknown' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=mgmt_cluster_security_group_id --mgmt-down')" = "1" ] || { echo "self-check FAILED: 기대 밖 가드(expected_mgmt_tags)가 override 와 같이 released 인데 FAIL 아님"; exit 1; }
  # --expect-released=mgmt_cluster_name (rename runbook step 1): 그 접두사만 INFO.
  # rename 중에는 mgmt 가 살아 있는 게 전제이므로 argocd 미도달은 여전히 FAIL.
  NAME_GUARD='["mgmt_cluster_name=mall-apne2-mgmt-v2 (trusting a cluster other than mall-apne2-mgmt)"]'
  [ "$(run_self_check "$NAME_GUARD" "$NAME_GUARD" 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Successful
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Successful' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=mgmt_cluster_name')" = "0" ] || { echo "self-check FAILED: --expect-released=mgmt_cluster_name 인데 rename 중 정상 argocd 상태로 FAIL"; exit 1; }
  [ "$(run_self_check "$NAME_GUARD" "$NAME_GUARD" 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Unknown
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Unknown' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=mgmt_cluster_name')" = "1" ] || { echo "self-check FAILED: --expect-released=mgmt_cluster_name 은 argocd 미도달을 INFO 로 내리면 안 됨(rename 중엔 mgmt 가 살아있어야 함)"; exit 1; }
  # round-12 M4-1: --expect-released=override 만으로는 argocd 미도달이 더 이상
  # INFO 로 내려가지 않는다 — --mgmt-down 을 명시해야 한다.
  [ "$(run_self_check "$OVERRIDE_GUARD" "$OVERRIDE_GUARD" 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Unknown
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Unknown' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=mgmt_cluster_security_group_id')" = "1" ] || { echo "self-check FAILED: --mgmt-down 없이 argocd 미도달이 INFO 로 내려감(M4-1)"; exit 1; }
  # round-12 m4-3: shared/ 변수명 그대로(_override 접미사)도 guard 이름으로 정규화된다.
  [ "$(run_self_check "$OVERRIDE_GUARD" "$OVERRIDE_GUARD" 'sg-mgmt' 'sg-mgmt' 'https://mgmt-a.example:6443 mall-apne2-az-a v1.30.0 Successful
https://mgmt-c.example:6443 mall-apne2-az-c v1.30.0 Successful' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=mgmt_cluster_security_group_id_override')" = "0" ] || { echo "self-check FAILED: _override 접미사가 guard 이름으로 정규화되지 않음"; exit 1; }
  # round-12 m4-3: 알 수 없는 guard 이름은 조용한 전체-FAIL 대신 usage 에러(2)다.
  [ "$(run_self_check '[]' '[]' 'sg-mgmt' 'sg-mgmt' '' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '--expect-released=bogus_guard')" = "2" ] || { echo "self-check FAILED: 알 수 없는 --expect-released 이름이 usage 에러(2)가 아님"; exit 1; }
  # round-12 M2-2: override 는 unset 인데 break_glass_confirm 만 true 로 남은 상태
  # (stale confirm — 다음 override 가 hard fail 없이 통과하게 되는 사전 disarm) 는 FAIL.
  [ "$(run_self_check '[]' '[]' 'sg-mgmt' 'sg-mgmt' '' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '' 'true')" = "1" ] || { echo "self-check FAILED: stale break_glass_confirm=true 인데 FAIL 아님(M2-2)"; exit 1; }
  # round-12 M2-1: 5개 trust 입력 전체를 덮는 fingerprint 가 shared↔spoke 에서
  # 갈리면(예: expected_mgmt_tags 만 shared 에 apply 되고 spoke 는 아직) FAIL.
  [ "$(run_self_check '[]' '[]' 'sg-mgmt' 'sg-mgmt' '' 'mall-apne2-mgmt' 'false' '' 'sg-mgmt' '' 'false' '"fp-stale"')" = "1" ] || { echo "self-check FAILED: fingerprint 미수렴(az-a stale)인데 FAIL 아님(M2-1)"; exit 1; }
  echo "self-check PASS (clean/released/guards-divergent/sg-divergent/unreadable/argocd-unreachable/argocd-stale-substring/shared-미수렴×2/expect-released-override/expect-released-mixed/expect-released-name/mgmt-down-분리/override-접미사-정규화/unknown-prefix-usage/stale-confirm/fingerprint-미수렴 모두 올바르게 판정)"
  exit 0
fi

# MGMT_GUARDS_{A,C}/MGMT_SG_{A,C}/MGMT_ARGOCD_STATUS/MGMT_SHARED_*/MGMT_LIVE_SG 는
# _MGMT_SELF_CHECK=1 일 때만 읽는다 — 이 게이팅이 없으면 이 스크립트가 유일하게
# `check` 블록의 경고를 종료 코드로 바꾸는 지점인데, 호출 환경에 이 이름의 변수가
# (의도든 우연이든) 설정돼 있으면 실제 terraform/argocd/aws 를 전혀 건드리지 않고
# PASS 를 조작할 수 있었다(round-9 리뷰 L3 MAJOR, 확인됨). `--self-check` 재귀 호출만
# 이 채널을 쓰므로 그 경로에서만 sentinel 을 세팅한다 — 일반 실행 경로에서는 항상
# 비어 있고 항상 실물을 읽는다.
read_output() {  # $1=layer-dir $2=output-name $3=env-var-name
  local dir="$1" name="$2" var="$3"
  if [ "${_MGMT_SELF_CHECK:-0}" = "1" ] && [ -n "${!var:-}" ]; then printf '%s' "${!var}"; return 0; fi
  terraform -chdir="$dir" output -json "$name" 2>/dev/null
}

for AZ in a c; do
  DIR="$LAYERS/eks-az-$AZ"
  GVAR="MGMT_GUARDS_${AZ^^}" SVAR="MGMT_SG_${AZ^^}"
  if [ "${_MGMT_SELF_CHECK:-0}" != "1" ] || [ -z "${!GVAR:-}" ]; then
    if [ ! -d "$DIR/.terraform" ]; then
      echo "FAIL az-$AZ: not initialized ($DIR) — run terraform init. 미초기화는 '검사 불가'이지 '정상'이 아니다."
      FAIL=1
      continue
    fi
  fi

  # -json 으로 읽는다: 사람이 읽는 출력은 빈 리스트를 "[]" 로도, 여러 줄로도 낼 수 있어
  # 문자열 비교로는 "가드 걸림"과 "출력 없음"을 구분할 수 없다.
  if ! RAW="$(read_output "$DIR" mgmt_guards_released "$GVAR")" || [ -z "$RAW" ]; then
    echo "FAIL az-$AZ: mgmt_guards_released 출력을 읽을 수 없음 — 이 레이어가 아직 apply 되지 않았거나 state 를 못 읽는다."
    FAIL=1
    continue
  fi
  if ! SG_RAW="$(read_output "$DIR" mgmt_trust_security_group_id "$SVAR")" || [ -z "$SG_RAW" ]; then
    echo "FAIL az-$AZ: mgmt_trust_security_group_id 출력을 읽을 수 없음."
    FAIL=1
    continue
  fi

  # RAW 가 유효한 JSON 리스트가 아니면(예: state 이상으로 null) len() 이 예외를 던지고
  # `set -e` 가 메시지 없이 스크립트를 죽인다 — "검사 실패"가 아니라 "검사기 침묵"이
  # 되는 것이 최악이라 여기서 명시적으로 잡는다(round-9 리뷰 L4 MINOR, 확인됨).
  if ! COUNT="$(printf '%s' "$RAW" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, list):
    sys.exit(1)
print(len(d))
')"; then
    echo "FAIL az-$AZ: mgmt_guards_released 이 리스트가 아니다(값: $RAW) — state 이상 가능성."
    FAIL=1
    continue
  fi
  if [ "$COUNT" -ne 0 ]; then
    # 기대한 접두사로 시작하지 않는 released 항목이 하나라도 있으면 FAIL — 기대
    # 범위 밖의 가드까지 --expect-released 가 조용히 삼키면 안 된다(round-11 리뷰
    # M6, 확인됨). EXPECT_RELEASED_PREFIXES 가 비어 있으면(plain 모드) 전부 "기대
    # 밖"이라 항상 FAIL — 기존 동작과 동일.
    UNEXPECTED_COUNT="$(printf '%s' "$RAW" | python3 -c '
import json, os, sys
prefixes = [p for p in os.environ.get("EXPECT_RELEASED_PREFIXES", "").split(",") if p]
guards = json.load(sys.stdin)
unexpected = [g for g in guards if not any(g.startswith(p + "=") for p in prefixes)]
print(len(unexpected))
')"
    if [ -n "$EXPECT_RELEASED_PREFIXES" ] && [ "$UNEXPECTED_COUNT" -eq 0 ]; then
      echo "INFO az-$AZ: 가드 $COUNT 개가 해제된 상태(--expect-released=$EXPECT_RELEASED_PREFIXES 지정 — 예상됨):"
    else
      if [ -n "$EXPECT_RELEASED_PREFIXES" ]; then
        echo "FAIL az-$AZ: 가드 $COUNT 개 중 $UNEXPECTED_COUNT 개가 --expect-released=$EXPECT_RELEASED_PREFIXES 의 예상 범위 밖이다:"
      else
        echo "FAIL az-$AZ: 가드 $COUNT 개가 해제된 상태로 apply 돼 있다:"
      fi
      FAIL=1
    fi
    printf '%s' "$RAW" | python3 -c 'import json,sys; [print("  - "+g) for g in json.load(sys.stdin)]'
  else
    echo "OK   az-$AZ: 모든 mgmt 신뢰 가드 engaged."
  fi
  eval "GUARDS_$AZ=\$RAW"
  eval "SG_$AZ=\$SG_RAW"

  # round-12 M2-1: 5개 trust 입력 전체를 덮는 fingerprint. 아래 3자 비교가 이것으로
  # name/override 밖의 나머지 입력(expected_mgmt_tags/vpc_id, default_mgmt_cluster_name)
  # 의 미수렴 창까지 잡는다.
  if FP_RAW="$(read_output "$DIR" mgmt_trust_fingerprint "MGMT_FP_${AZ^^}")" && [ -n "$FP_RAW" ]; then
    eval "FP_$AZ=\$FP_RAW"
  else
    echo "FAIL az-$AZ: mgmt_trust_fingerprint 출력을 읽을 수 없음 — 이 레이어를 이 output 이 추가된 변경 이후로 아직 apply 하지 않았다."
    FAIL=1
  fi
done

# 수렴 확인 — 값이 다르면 한쪽만 apply 됐다는 뜻이다(shared/ 는 이미 단일 소스라
# "서로 다른 값을 요구받는" 경로는 없다). 한쪽 ArgoCD 만 도달 가능한 상태에서
# 스키마 마이그레이션이 fleet 절반에만 닿는 것이 이 검사가 막는 것. --expect-released
# 여도 이 비교는 항상 hard FAIL 이다 — break-glass 중 두 spoke 가 같은 값으로
# 수렴했는지가 이 모드가 검증해야 하는 핵심이기 때문.
if [ -n "${GUARDS_a:-}" ] && [ -n "${GUARDS_c:-}" ] && [ "$GUARDS_a" != "$GUARDS_c" ]; then
  echo "FAIL 두 spoke 의 mgmt_guards_released 가 다르다 — shared/ 변경이 한쪽에만 apply 된 상태다."
  echo "  az-a: $GUARDS_a"
  echo "  az-c: $GUARDS_c"
  echo "  두 레이어 모두 apply 한 뒤 다시 실행할 것 (terraform/environments/production/ap-northeast-2/README.md Runbooks)."
  FAIL=1
fi
if [ -n "${SG_a:-}" ] && [ -n "${SG_c:-}" ] && [ "$SG_a" != "$SG_c" ]; then
  echo "FAIL 두 spoke 가 신뢰하는 mgmt SG ID 가 다르다 — released_guards 는 수렴해 보여도 실제 SG 가 갈렸다."
  echo "  az-a: $SG_a"
  echo "  az-c: $SG_c"
  echo "  mgmt 가 재생성됐을 가능성 — 두 레이어 모두 apply 한 뒤 다시 실행할 것."
  FAIL=1
fi

# shared/ 의 *현재* 값과 3자 비교 — 위 두 비교는 spoke끼리만 맞춰봐서, "shared/ 에
# override·이름 변경을 commit·apply 했지만 두 spoke 모두 아직 재apply 하지 않은" 창을
# 놓친다(round-9 리뷰 L4 MAJOR, 확인됨): 그 창에서는 두 spoke 가 여전히 옛 값에
# 수렴해 있어 위 비교가 PASS 를 낸다. shared/ 가 지금 무엇을 신뢰하라고 선언 중인지
# 직접 읽어 비교해야 그 창이 잡힌다.
#
# override 는 _set/_value 두 output 으로 읽는다(round-10 리뷰 CRITICAL, 확인됨) —
# 이전에는 override 하나를 null|""|"sg-..." 로 노출했는데, terraform 은 null 값
# root output 을 state 의 outputs 맵에 아예 쓰지 않아 "output 이 없다"와 "값이
# null이다"를 구분할 수 없었다. shared/outputs.tf 의 두 output 설명 참조.
SHARED_DIR="$LAYERS/shared"
if [ "${_MGMT_SELF_CHECK:-0}" != "1" ] && [ ! -d "$SHARED_DIR/.terraform" ]; then
  echo "FAIL shared/: not initialized ($SHARED_DIR) — run terraform init. shared/ 의 현재 신뢰 대상을 확인할 수 없다."
  FAIL=1
elif SHARED_NAME_RAW="$(read_output "$SHARED_DIR" mgmt_cluster_name MGMT_SHARED_NAME)" && [ -n "$SHARED_NAME_RAW" ] \
  && OVERRIDE_SET_RAW="$(read_output "$SHARED_DIR" mgmt_cluster_security_group_id_override_set MGMT_SHARED_OVERRIDE_SET)" && [ -n "$OVERRIDE_SET_RAW" ] \
  && OVERRIDE_VALUE_RAW="$(read_output "$SHARED_DIR" mgmt_cluster_security_group_id_override_value MGMT_SHARED_OVERRIDE_VALUE)" && [ -n "$OVERRIDE_VALUE_RAW" ]; then

  OVERRIDE_IS_SET="$(printf '%s' "$OVERRIDE_SET_RAW" | python3 -c 'import json,sys; print("1" if json.load(sys.stdin) else "0")' 2>/dev/null || echo "__PARSE_ERROR__")"
  EXPECTED_SG="$(printf '%s' "$OVERRIDE_VALUE_RAW" | python3 -c 'import json,sys; print(json.load(sys.stdin))' 2>/dev/null || echo "__PARSE_ERROR__")"

  if [ "$OVERRIDE_IS_SET" = "__PARSE_ERROR__" ] || [ "$EXPECTED_SG" = "__PARSE_ERROR__" ]; then
    echo "FAIL shared/: mgmt_cluster_security_group_id_override_set/_value 출력을 파싱할 수 없다(값: $OVERRIDE_SET_RAW / $OVERRIDE_VALUE_RAW)."
    FAIL=1
  elif [ "$OVERRIDE_IS_SET" = "1" ]; then
    # break-glass 경로: shared/ 가 이미 override 값을 선언 중이다. 두 spoke 가 그
    # 값을 집어갔는지 직접 비교.
    for AZ in a c; do
      SG_VAR="SG_$AZ"
      SG_VAL="${!SG_VAR:-}"
      if [ -n "$SG_VAL" ]; then
        SG_ACTUAL="$(printf '%s' "$SG_VAL" | python3 -c 'import json,sys; print(json.load(sys.stdin))' 2>/dev/null || echo "$SG_VAL")"
        if [ "$SG_ACTUAL" != "$EXPECTED_SG" ]; then
          echo "FAIL az-$AZ: shared/ 는 이미 mgmt_cluster_security_group_id_override=${EXPECTED_SG:-<empty>} 를 신뢰하라고 선언 중인데, 이 spoke 는 여전히 ${SG_ACTUAL} 를 신뢰한다 — 아직 재apply 되지 않았다."
          FAIL=1
        fi
      fi
    done
  else
    # 정상 경로(override 없음): shared/ 가 지금 가리키는 mgmt_cluster_name 을 live 로
    # 조회해 그 SG 를 각 spoke 의 SG 와 비교한다. mgmt 는 항상 ap-northeast-2 이므로
    # --region 을 명시한다 — 없으면 셸의 기본 리전(이 저장소의 backend/state 는
    # us-east-1 이라 그쪽일 확률이 높다)으로 나가 응답이 비어 FAIL 로 오진된다
    # (round-10 리뷰 MAJOR, 확인됨). aws CLI 가 없으면 이 창을 검증할 수단이 없다는
    # 뜻이므로 — 기존 argocd-CLI-부재 처리와 같은 정책으로 — 조용히 넘기지 않고
    # FAIL 로 낸다.
    if [ "${_MGMT_SELF_CHECK:-0}" = "1" ] && [ -n "${MGMT_LIVE_SG:-}" ]; then
      LIVE_SG="$MGMT_LIVE_SG"
    elif command -v aws >/dev/null 2>&1; then
      MGMT_NAME="$(printf '%s' "$SHARED_NAME_RAW" | python3 -c 'import json,sys; print(json.load(sys.stdin))' 2>/dev/null || echo "")"
      LIVE_SG="$(aws eks describe-cluster --region "$MGMT_REGION" --name "$MGMT_NAME" --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text 2>/dev/null || echo "")"
      if [ -z "$LIVE_SG" ] || [ "$LIVE_SG" = "None" ]; then
        echo "FAIL shared/: aws eks describe-cluster --region $MGMT_REGION $MGMT_NAME 로 live SG 를 확인할 수 없다 — mgmt 도달성 자체를 점검할 것."
        FAIL=1
        LIVE_SG=""
      fi
    else
      echo "FAIL shared/: aws CLI 없음 — shared/ 가 지금 가리키는 mgmt 의 live SG 를 확인할 수 없다."
      FAIL=1
      LIVE_SG=""
    fi
    if [ -n "$LIVE_SG" ]; then
      for AZ in a c; do
        SG_VAR="SG_$AZ"
        SG_VAL="${!SG_VAR:-}"
        if [ -n "$SG_VAL" ]; then
          SG_ACTUAL="$(printf '%s' "$SG_VAL" | python3 -c 'import json,sys; print(json.load(sys.stdin))' 2>/dev/null || echo "$SG_VAL")"
          if [ "$SG_ACTUAL" != "$LIVE_SG" ]; then
            echo "FAIL az-$AZ: shared/ 가 가리키는 mgmt 클러스터의 현재 live SG 는 ${LIVE_SG} 인데, 이 spoke 는 여전히 ${SG_ACTUAL} 를 신뢰한다 — mgmt 이름 변경/재생성이 아직 이 spoke 에 반영되지 않았다."
            FAIL=1
          fi
        fi
      done
    fi
  fi
else
  echo "FAIL shared/: mgmt_cluster_name 또는 mgmt_cluster_security_group_id_override_set/_value 출력을 읽을 수 없다 — shared/ 가 아직 apply 되지 않았거나 state 를 못 읽는다."
  FAIL=1
fi

# round-12 M2-2: break_glass_confirm 은 released_guards 대상이 아니라서(trust 입력이
# 아니다) 어떤 가드 리포팅에도 안 나타났다 — override 를 unset 하며 confirm 만 true 로
# 남기면 다음 override 설정이 hard fail 없이 통과한다(preventive gate 의 사전 disarm).
# 그 상태를 여기서 FAIL 로 낸다.
if CONFIRM_RAW="$(read_output "$SHARED_DIR" break_glass_confirm MGMT_SHARED_CONFIRM)" && [ -n "$CONFIRM_RAW" ]; then
  CONFIRM_IS_TRUE="$(printf '%s' "$CONFIRM_RAW" | python3 -c 'import json,sys; print("1" if json.load(sys.stdin) else "0")' 2>/dev/null || echo "__PARSE_ERROR__")"
  if [ "$CONFIRM_IS_TRUE" = "__PARSE_ERROR__" ]; then
    echo "FAIL shared/: break_glass_confirm 출력을 파싱할 수 없다(값: $CONFIRM_RAW)."
    FAIL=1
  elif [ "$CONFIRM_IS_TRUE" = "1" ] && [ "${OVERRIDE_IS_SET:-}" = "0" ]; then
    echo "FAIL shared/: break_glass_confirm=true 인데 override 는 unset — stale confirm 이다. 이대로 두면 다음 override 설정이 break_glass_gate 를 hard fail 없이 통과한다. shared/terraform.tfvars 에서 break_glass_confirm 을 제거(또는 false)하고 apply 할 것."
    FAIL=1
  fi
else
  echo "FAIL shared/: break_glass_confirm 출력을 읽을 수 없다 — shared/ 를 이 output 이 추가된 변경 이후로 아직 apply 하지 않았거나 state 를 못 읽는다."
  FAIL=1
fi

# round-12 M2-1: shared↔az-a↔az-c 의 5-입력 fingerprint 3자 비교. 위의 name/override
# 비교는 유지한다(어느 값이 왜 갈렸는지 메시지가 구체적이다) — 이 비교는 그 둘이
# 못 보는 나머지 입력의 미수렴 창을 닫는 포괄 검사다. 입력이 늘어도(모듈과 shared/
# 의 fingerprint output 두 곳만 같이 늘리면) 이 스크립트는 수정이 필요 없다.
if FP_SHARED_RAW="$(read_output "$SHARED_DIR" mgmt_trust_fingerprint MGMT_SHARED_FP)" && [ -n "$FP_SHARED_RAW" ]; then
  for AZ in a c; do
    FP_VAR="FP_$AZ"
    FP_VAL="${!FP_VAR:-}"
    if [ -n "$FP_VAL" ] && [ "$FP_VAL" != "$FP_SHARED_RAW" ]; then
      echo "FAIL az-$AZ: mgmt trust fingerprint 가 shared/ 와 다르다 — 5개 trust 입력 중 무언가(expected_mgmt_tags/expected_mgmt_vpc_id/default_mgmt_cluster_name 포함)가 shared/ 에 apply 된 뒤 이 spoke 가 아직 재apply 되지 않았다."
      FAIL=1
    fi
  done
else
  echo "FAIL shared/: mgmt_trust_fingerprint 출력을 읽을 수 없다 — shared/ 를 이 output 이 추가된 변경 이후로 아직 apply 하지 않았거나 state 를 못 읽는다."
  FAIL=1
fi

# ArgoCD 가 실제로 두 클러스터에 도달하는지 — SG 가 맞아도 mgmt 가 재생성됐으면
# 조용히 죽어 있을 수 있다(ADR-003 의 stale-SG follow-up 이 다루는 실패 양식).
# 두 spoke 모두 Successful 이어야 통과 — CLI 부재/명령 실패/Unknown 상태는 전부 FAIL,
# 단 --expect-released=mgmt_cluster_security_group_id 에서는 INFO(break-glass 중
# mgmt 자체가 죽어 있으므로 예상됨). rename(--expect-released=mgmt_cluster_name)
# 에서는 mgmt 가 살아 있는 게 전제이므로 이 다운그레이드를 적용하지 않는다.
#
# ARGO_RAW 를 구하는 세 경로(주입/CLI 성공/CLI 실패) 모두 검증 루프를 반드시 통과해야
# 한다. round-8 리뷰가 잡은 버그: `argocd cluster list ... || true` 가 명령 실패(인증
# 만료 등)를 빈 문자열로 흡수한 뒤, 그 빈 문자열을 `[ -n "$ARGO_RAW" ]` 로만 검사해
# **루프 전체를 건너뛰어** FAIL 이 전혀 설정되지 않았다 — "CLI 부재/명령 실패/Unknown
# 전부 FAIL" 이라는 주석의 주장과 실제 코드가 반대였다. 이제 명령의 종료 코드를
# 직접 검사해 실패를 이 지점에서 즉시 FAIL 로 잡고, 아래 루프는 조건 없이 항상 돈다 —
# ARGO_RAW 가 진짜로 비어 있어도(등록된 클러스터 0개) 각 AZ 가 "등록 안 됨"으로 FAIL
# 하도록 만든다.
argo_report() {  # $1=message
  if [ "$EXPECT_MGMT_DOWN" = "1" ]; then
    echo "INFO $1 (--mgmt-down 지정 — mgmt 다운 중이므로 예상됨)"
  else
    echo "FAIL $1"
    FAIL=1
  fi
}

if [ "${_MGMT_SELF_CHECK:-0}" = "1" ] && [ -n "${MGMT_ARGOCD_STATUS:-}" ]; then
  ARGO_RAW="$MGMT_ARGOCD_STATUS"
elif command -v argocd >/dev/null 2>&1; then
  if ! ARGO_LIST="$(argocd cluster list 2>/dev/null)"; then
    argo_report "argocd cluster list 명령이 실패했다(인증 만료/네트워크 등) — 도달성을 검증할 수 없다."
    ARGO_RAW=""
  else
    ARGO_RAW="$(printf '%s\n' "$ARGO_LIST" | grep -E "mall-apne2-az-(a|c)" || true)"
  fi
else
  argo_report "argocd CLI 없음 — 도달성을 검증할 수 없다. mgmt 클러스터에서 실행하거나 CLI 를 설치할 것."
  ARGO_RAW=""
fi

for AZ in a c; do
  # `argocd cluster list` 컬럼은 SERVER NAME VERSION STATUS MESSAGE PROJECT —
  # 이름은 두 번째 필드, 첫 필드는 API server URL 이다. round-9 의 `$1==n` 은 이
  # contract 를 거꾸로 가정해 정상 등록된 클러스터도 "미등록"으로 오판했다(round-10
  # 리뷰 MAJOR, 확인됨 — self-check 픽스처가 2컬럼 name-first 합성값이라 이 회귀를
  # 구조적으로 잡지 못했다. 위 self-check 는 이제 실제 컬럼 순서로 픽스처를 낸다).
  LINE="$(printf '%s\n' "$ARGO_RAW" | awk -v n="mall-apne2-az-$AZ" '$2==n {print; exit}')"
  if [ -z "$LINE" ]; then
    argo_report "az-$AZ: argocd cluster list 에 등록되어 있지 않다(또는 위 명령 실패로 목록 자체를 못 받았다)."
  elif ! printf '%s' "$LINE" | grep -q "Successful"; then
    argo_report "az-$AZ: argocd 도달 상태가 Successful 이 아니다: $LINE"
  else
    echo "OK   az-$AZ: argocd 도달 확인 (Successful)."
  fi
done

[ "$FAIL" -eq 0 ] && echo "PASS mgmt 신뢰 경계 정상." || echo "FAILED — 위 항목 확인."
exit "$FAIL"

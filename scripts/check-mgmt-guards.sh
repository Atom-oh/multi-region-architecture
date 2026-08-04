#!/usr/bin/env bash
# mgmt 신뢰 경계 검사 — 두 spoke 가 (1) 가드를 다 걸고 있고 (2) 서로 수렴했는지 확인.
#
# 왜 스크립트인가: 모듈의 `check "mgmt_guards_engaged"` 는 plan 을 실패시키지 않는다
# (그게 check 블록의 정의다) — 가드가 해제된 plan 은 걸린 plan 과 출력이 다를 뿐,
# 종료 코드가 같다. 그래서 "가드 해제는 경고"라는 상태가 남는다. 이 스크립트가 그
# 경고를 종료 코드로 바꾼다: break-glass 후 복구 확인, 또는 apply 전 사전 점검용.
#
# 그리고 single-sourcing 은 두 spoke 가 *같은 값을 요구받는다*만 보장한다 — 각자
# apply 를 해야 실제로 반영되므로, 한쪽만 apply 된 창이 존재한다. 그 창은 값의 비교로만
# 잡히고, 이 스크립트가 그걸 한다.
#
# ponytail: 수동 실행. 스케줄러(cron/Actions)로 만들지 않는다 — 프로덕션에 무기한
# 도는 자동화를 리뷰 지적 하나로 새로 들이지 않는다는 게 이 저장소의 방침이고,
# stale-SG 상시 감지는 ADR-003 의 follow-up 으로 별도 추적된다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAYERS="$ROOT/terraform/environments/production/ap-northeast-2"
FAIL=0

# --self-check: 판정 로직만 검증한다(AWS 접근 없음). 이 스크립트가 잡아야 하는 상태들 —
# 둘 다 깨끗함 / 한쪽 가드 해제 / guards 값 불일치 / SG 값 불일치 / 한쪽 미초기화 /
# argocd 미도달 — 을 주입해 종료 코드가 실제로 갈리는지 확인한다. 가드 검사기 자체가
# 조용히 통과하는 것이 최악의 실패다.
if [ "${1:-}" = "--self-check" ]; then
  run() {
    MGMT_GUARDS_A="${1:-}" MGMT_GUARDS_C="${2:-}" \
    MGMT_SG_A="${3:-sg-mgmt}" MGMT_SG_C="${4:-sg-mgmt}" \
    MGMT_ARGOCD_STATUS="${5:-mall-apne2-az-a Successful
mall-apne2-az-c Successful}" \
    bash "$0" >/dev/null 2>&1; echo $?
  }
  [ "$(run '[]' '[]')" = "0" ] || { echo "self-check FAILED: 둘 다 깨끗한데 PASS 아님"; exit 1; }
  [ "$(run '["x"]' '["x"]')" = "1" ] || { echo "self-check FAILED: 양쪽 가드 해제인데 FAIL 아님"; exit 1; }
  [ "$(run '[]' '["x"]')" = "1" ] || { echo "self-check FAILED: guards 불일치인데 FAIL 아님"; exit 1; }
  [ "$(run '[]' '[]' 'sg-old' 'sg-new')" = "1" ] || { echo "self-check FAILED: SG 불일치인데 FAIL 아님"; exit 1; }
  [ "$(run '' '[]')" = "1" ] || { echo "self-check FAILED: 한쪽 read 실패인데 FAIL 아님"; exit 1; }
  [ "$(run '[]' '[]' 'sg-mgmt' 'sg-mgmt' 'mall-apne2-az-a Successful
mall-apne2-az-c Unknown')" = "1" ] || { echo "self-check FAILED: argocd 미도달인데 FAIL 아님"; exit 1; }
  echo "self-check PASS (clean/released/guards-divergent/sg-divergent/unreadable/argocd-unreachable 모두 올바르게 판정)"
  exit 0
fi

# MGMT_GUARDS_{A,C}/MGMT_SG_{A,C}/MGMT_ARGOCD_STATUS 가 있으면 terraform/argocd 대신
# 그 값을 읽는다 — --self-check 가 실제 state·CLI 없이 판정 로직을 돌리기 위한 주입점.
# self-check 재귀 호출에서만 쓰이는 내부 채널이라, 이 스크립트를 직접 실행하는 일반
# 경로에서는 항상 비어 있고 항상 terraform/argocd 를 읽는다.
read_output() {  # $1=a|c $2=output-name $3=env-var-name
  local az="$1" name="$2" var="$3"
  if [ -n "${!var:-}" ]; then printf '%s' "${!var}"; return 0; fi
  terraform -chdir="$LAYERS/eks-az-$az" output -json "$name" 2>/dev/null
}

for AZ in a c; do
  DIR="$LAYERS/eks-az-$AZ"
  GVAR="MGMT_GUARDS_${AZ^^}" SVAR="MGMT_SG_${AZ^^}"
  if [ -z "${!GVAR:-}" ] && [ ! -d "$DIR/.terraform" ]; then
    echo "FAIL az-$AZ: not initialized ($DIR) — run terraform init. 미초기화는 '검사 불가'이지 '정상'이 아니다."
    FAIL=1
    continue
  fi

  # -json 으로 읽는다: 사람이 읽는 출력은 빈 리스트를 "[]" 로도, 여러 줄로도 낼 수 있어
  # 문자열 비교로는 "가드 걸림"과 "출력 없음"을 구분할 수 없다.
  if ! RAW="$(read_output "$AZ" mgmt_guards_released "$GVAR")" || [ -z "$RAW" ]; then
    echo "FAIL az-$AZ: mgmt_guards_released 출력을 읽을 수 없음 — 이 레이어가 아직 apply 되지 않았거나 state 를 못 읽는다."
    FAIL=1
    continue
  fi
  if ! SG_RAW="$(read_output "$AZ" mgmt_trust_security_group_id "$SVAR")" || [ -z "$SG_RAW" ]; then
    echo "FAIL az-$AZ: mgmt_trust_security_group_id 출력을 읽을 수 없음."
    FAIL=1
    continue
  fi

  COUNT="$(printf '%s' "$RAW" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
  if [ "$COUNT" -ne 0 ]; then
    echo "FAIL az-$AZ: 가드 $COUNT 개가 해제된 상태로 apply 돼 있다:"
    printf '%s' "$RAW" | python3 -c 'import json,sys; [print("  - "+g) for g in json.load(sys.stdin)]'
    FAIL=1
  else
    echo "OK   az-$AZ: 모든 mgmt 신뢰 가드 engaged."
  fi
  eval "GUARDS_$AZ=\$RAW"
  eval "SG_$AZ=\$SG_RAW"
done

# 수렴 확인 — 값이 다르면 한쪽만 apply 됐다는 뜻이다(shared/ 는 이미 단일 소스라
# "서로 다른 값을 요구받는" 경로는 없다). 한쪽 ArgoCD 만 도달 가능한 상태에서
# 스키마 마이그레이션이 fleet 절반에만 닿는 것이 이 검사가 막는 것.
#
# released_guards 만 비교하면 정상 상태(양쪽 다 [])가 mgmt replace 이후 한쪽만
# 재-apply 된 상태를 가려버린다 — 그 경우 guards 는 둘 다 [] 로 수렴해 보이지만
# 실제로 신뢰하는 SG ID 자체가 다르다. 그래서 resolved SG ID 도 함께 비교한다.
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

# ArgoCD 가 실제로 두 클러스터에 도달하는지 — SG 가 맞아도 mgmt 가 재생성됐으면
# 조용히 죽어 있을 수 있다(ADR-003 의 stale-SG follow-up 이 다루는 실패 양식).
# 두 spoke 모두 Successful 이어야 통과 — CLI 부재/명령 실패/Unknown 상태는 전부 FAIL.
#
# ARGO_RAW 를 구하는 세 경로(주입/CLI 성공/CLI 실패) 모두 검증 루프를 반드시 통과해야
# 한다. round-8 리뷰가 잡은 버그: `argocd cluster list ... || true` 가 명령 실패(인증
# 만료 등)를 빈 문자열로 흡수한 뒤, 그 빈 문자열을 `[ -n "$ARGO_RAW" ]` 로만 검사해
# **루프 전체를 건너뛰어** FAIL 이 전혀 설정되지 않았다 — "CLI 부재/명령 실패/Unknown
# 전부 FAIL" 이라는 주석의 주장과 실제 코드가 반대였다. 이제 명령의 종료 코드를
# 직접 검사해 실패를 이 지점에서 즉시 FAIL 로 잡고, 아래 루프는 조건 없이 항상 돈다 —
# ARGO_RAW 가 진짜로 비어 있어도(등록된 클러스터 0개) 각 AZ 가 "등록 안 됨"으로 FAIL
# 하도록 만든다.
if [ -n "${MGMT_ARGOCD_STATUS:-}" ]; then
  ARGO_RAW="$MGMT_ARGOCD_STATUS"
elif command -v argocd >/dev/null 2>&1; then
  if ! ARGO_LIST="$(argocd cluster list 2>/dev/null)"; then
    echo "FAIL argocd cluster list 명령이 실패했다(인증 만료/네트워크 등) — 도달성을 검증할 수 없다."
    FAIL=1
    ARGO_RAW=""
  else
    ARGO_RAW="$(printf '%s\n' "$ARGO_LIST" | grep -E "mall-apne2-az-(a|c)" || true)"
  fi
else
  echo "FAIL argocd CLI 없음 — 도달성을 검증할 수 없다. mgmt 클러스터에서 실행하거나 CLI 를 설치할 것."
  FAIL=1
  ARGO_RAW=""
fi

for AZ in a c; do
  LINE="$(printf '%s\n' "$ARGO_RAW" | grep "mall-apne2-az-$AZ" || true)"
  if [ -z "$LINE" ]; then
    echo "FAIL az-$AZ: argocd cluster list 에 등록되어 있지 않다(또는 위 명령 실패로 목록 자체를 못 받았다)."
    FAIL=1
  elif ! printf '%s' "$LINE" | grep -q "Successful"; then
    echo "FAIL az-$AZ: argocd 도달 상태가 Successful 이 아니다: $LINE"
    FAIL=1
  else
    echo "OK   az-$AZ: argocd 도달 확인 (Successful)."
  fi
done

[ "$FAIL" -eq 0 ] && echo "PASS mgmt 신뢰 경계 정상." || echo "FAILED — 위 항목 확인."
exit "$FAIL"

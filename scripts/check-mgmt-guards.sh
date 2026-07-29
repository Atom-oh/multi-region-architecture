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

# --self-check: 판정 로직만 검증한다(AWS 접근 없음). 이 스크립트가 잡아야 하는 세 가지
# 상태 — 둘 다 깨끗함 / 한쪽 가드 해제 / 값 불일치(한쪽만 apply) — 를 주입해 종료 코드가
# 실제로 갈리는지 확인한다. 가드 검사기 자체가 조용히 통과하는 것이 최악의 실패다.
if [ "${1:-}" = "--self-check" ]; then
  run() { MGMT_GUARDS_A="$1" MGMT_GUARDS_C="$2" bash "$0" >/dev/null 2>&1; echo $?; }
  [ "$(run '[]' '[]')" = "0" ] || { echo "self-check FAILED: 둘 다 깨끗한데 PASS 아님"; exit 1; }
  [ "$(run '["x"]' '["x"]')" = "1" ] || { echo "self-check FAILED: 양쪽 가드 해제인데 FAIL 아님"; exit 1; }
  [ "$(run '[]' '["x"]')" = "1" ] || { echo "self-check FAILED: 불일치인데 FAIL 아님"; exit 1; }
  echo "self-check PASS (clean/released/divergent 세 상태 모두 올바르게 판정)"
  exit 0
fi

# MGMT_GUARDS_{A,C} 가 있으면 terraform 대신 그 값을 읽는다 — --self-check 가 state 없이
# 판정 로직(빈/비빈, 수렴)을 실제로 돌리기 위한 주입점.
read_guards() {  # $1=a|c
  local az="$1" var="MGMT_GUARDS_${1^^}"
  if [ -n "${!var:-}" ]; then printf '%s' "${!var}"; return 0; fi
  terraform -chdir="$LAYERS/eks-az-$az" output -json mgmt_guards_released 2>/dev/null
}

for AZ in a c; do
  DIR="$LAYERS/eks-az-$AZ"
  VAR="MGMT_GUARDS_${AZ^^}"
  if [ -z "${!VAR:-}" ] && [ ! -d "$DIR/.terraform" ]; then
    echo "SKIP az-$AZ: not initialized ($DIR) — run terraform init"
    continue
  fi

  # -json 으로 읽는다: 사람이 읽는 출력은 빈 리스트를 "[]" 로도, 여러 줄로도 낼 수 있어
  # 문자열 비교로는 "가드 걸림"과 "출력 없음"을 구분할 수 없다.
  if ! RAW="$(read_guards "$AZ")" || [ -z "$RAW" ]; then
    echo "FAIL az-$AZ: mgmt_guards_released 출력을 읽을 수 없음 — 이 레이어가 아직 apply 되지 않았거나 state 를 못 읽는다."
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
done

# 수렴 확인 — 값이 다르면 한쪽만 apply 됐다는 뜻이다(shared/ 는 이미 단일 소스라
# "서로 다른 값을 요구받는" 경로는 없다). 한쪽 ArgoCD 만 도달 가능한 상태에서
# 스키마 마이그레이션이 fleet 절반에만 닿는 것이 이 검사가 막는 것.
if [ -n "${GUARDS_a:-}" ] && [ -n "${GUARDS_c:-}" ] && [ "$GUARDS_a" != "$GUARDS_c" ]; then
  echo "FAIL 두 spoke 의 mgmt_guards_released 가 다르다 — shared/ 변경이 한쪽에만 apply 된 상태다."
  echo "  az-a: $GUARDS_a"
  echo "  az-c: $GUARDS_c"
  echo "  두 레이어 모두 apply 한 뒤 다시 실행할 것 (terraform/environments/production/ap-northeast-2/README.md Runbooks)."
  FAIL=1
fi

# ArgoCD 가 실제로 두 클러스터에 도달하는지 — SG 가 맞아도 mgmt 가 재생성됐으면
# 조용히 죽어 있을 수 있다(ADR-003 의 stale-SG follow-up 이 다루는 실패 양식).
if command -v argocd >/dev/null 2>&1; then
  echo "--- argocd cluster list (mall-apne2-az-a/c 가 Successful 이어야 한다) ---"
  argocd cluster list 2>&1 | grep -E "SERVER|mall-apne2-az-" || echo "  (등록된 spoke 클러스터 없음)"
else
  echo "NOTE argocd CLI 없음 — 도달성 확인은 수동으로: argocd cluster list (mgmt 클러스터에서)"
fi

[ "$FAIL" -eq 0 ] && echo "PASS mgmt 신뢰 경계 정상." || echo "FAILED — 위 항목 확인."
exit "$FAIL"

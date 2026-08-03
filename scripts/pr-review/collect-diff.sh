#!/usr/bin/env bash
# PR 변경 목록을 분류하고 패널에 넘길 diff 를 **재구성**한다.
# 인자: <files.json> <workdir>
#   files.json = `gh api repos/{owner}/{repo}/pulls/{n}/files` 의 결과 배열.
#
# 왜 `gh pr diff` 텍스트를 파싱하지 않는가 — 이게 이 파일이 존재하는 이유다.
# 이전 구현은 `diff --git` 헤더 문자열에서 경로를 뽑았고, 그 자리에 fail-open 이 두 개
# 겹쳐 있었다:
#
#   1. rename 은 old 와 new 가 다르고, 헤더에서 실용적으로 뽑히는 건 old 쪽이다.
#      `git mv a.tfstate y.txt` → `diff --git a/a.tfstate b/y.txt`. old 경로 뒤에 오는
#      것은 줄끝이 아니라 **공백**이므로 `\.tfstate($|\.|[0-9])` 의 세 분기 전부 실패하고,
#      new 경로는 `.txt` 라 애초에 안 걸린다. state deny 가 조용히 통과한다.
#   2. git 은 비-ASCII·공백 경로를 `diff --git "a/..." "b/..."` 로 **인용**한다.
#      `^diff --git a/` 앵커가 `"a/` 에 매치되지 않아 인용된 경로 전체가 모든 검사에서
#      투명해진다.
#
# 두 구멍은 같은 뿌리에서 나온다: diff 헤더는 경로의 신뢰할 수 있는 표현이 아니다.
# 그래서 헤더를 더 정교하게 파싱하는 대신 파싱을 없앤다. `pulls/{n}/files` 는 파일당
# `filename` / `previous_filename` / `status` / `patch` 를 **JSON 값**으로 준다 —
# 인용 없음, 헤더 없음, rename 의 두 경로가 별도 필드. 패널 diff 는 그 목록에서 고른
# 파일의 `patch` 로 재구성한다. 고르지 않은 파일의 내용은 어떤 출력 파일에도 실리지
# 않으므로, "제외했는데 헝크는 새어나갔다"가 구조적으로 불가능해진다.
#
# 출력(workdir 안):
#   panel.diff            패널이 읽을 재구성 diff
#   classified.tsv        분류 결과 원본(klass, f, prev, status, binary, asset)
#   fatal-state.txt       state/plan 이면서 삭제가 아닌 경로 → 잡을 죽인다
#   fatal-badpath.txt     경로에 제어문자 → 잡을 죽인다
#   deleted-state.txt     state/plan 삭제 경로 → 통과시키되 내용은 전달하지 않는다
#   filtered.txt          패널에서 제외된 경로 전부
#   unsafe-filtered.txt   제외되었지만 auto-PASS 자격을 박탈하는 경로
#   fatal-oversized.txt   noise 가 아닌데 patch 가 없고 실변경이 있는 경로(= diff 가
#                         너무 커서 API 가 patch 를 생략한 텍스트 파일) → 잡을 죽인다
#   all-paths.txt         PR 이 건드린 경로 전부(rename 의 old 경로 포함)
# 종료 코드: 2 = fatal 있음, 1 = 사용법/입력 오류, 0 = 정상.
set -uo pipefail

FILES_JSON="${1:-}"; WORK="${2:-}"
[ -n "$FILES_JSON" ] || { echo "collect-diff.sh: files.json (\$1) required" >&2; exit 1; }
[ -n "$WORK" ] || { echo "collect-diff.sh: workdir (\$2) must not be empty" >&2; exit 1; }
[ -s "$FILES_JSON" ] || { echo "collect-diff.sh: $FILES_JSON is empty — refusing (fail-closed)" >&2; exit 1; }
mkdir -p "$WORK" || { echo "collect-diff.sh: cannot create $WORK" >&2; exit 1; }

# state/plan 패턴. 전부 경로 세그먼트에 앵커한다 — 이전 판의 `\.tfplan` 은 앵커가 없어서
# `docs/notes.tfplan.md` 같은 **문서**가 잡을 죽였다. `.tfstate.backup`, `.tfstate.1`,
# 확장자 없는 `tfplan`/`plan.out`, `terraform.tfstate.d/`, 그리고 `plan.json`/`tfplan.json`
# (`terraform show -json` 산출물 — state 와 같은 평문 자격증명을 담는다) 을 덮는다.
STATE_RE='(^|/)[^/]*\.tfstate(\.[0-9]+)?(\.backup)?$|(^|/)[^/]*\.tfplan$|(^|/)(tf)?plan\.json$|(^|/)tfplan$|(^|/)plan\.out$|(^|/)terraform\.tfstate\.d/'

# 패널이 읽어도 의미가 없는 노이즈. 확장자 allow-list 는 여기 **없다** — 이전 판은
# `\.(png|pdf|zip|...)$` 로 경로를 걸러서, 같은 확장자를 가진 *텍스트* 파일이 혼합 PR
# 에서 어떤 렌즈에도 노출되지 않고 사라졌다. 가시성은 확장자가 아니라 "읽을 수 있는
# 텍스트인가"(= API 가 patch 를 주는가)가 결정한다.
# 이 목록을 넓히면 auto-PASS 후보도 함께 넓어진다 — 반드시
# docs/decisions/ADR-004-pr-review-empty-diff-exception.md 를 같이 갱신할 것.
# .terraform.lock.hcl 은 의도적으로 제외하지 않는다(ADR-004 §5).
#
# is_noise 는 반드시 new path(.filename) 단독으로만 판정한다 — old/new 중 하나만
# 노이즈여도 제외하면(`any`), `git mv src/frontend/package-lock.json terraform/waf.tf`
# 처럼 실제 IaC 변경을 노이즈 경로로 rename 해서 패널·게이트 양쪽에서 숨길 수 있다
# (PR#34 리뷰 L3 CRITICAL — is_asset 이 정확히 반대 이유로 `all` 을 쓰는 것과 대비된다:
# rename 자격 박탈은 두 경로 모두 요구해야 안전하고, 노이즈 제외는 새 경로 하나만
# 봐야 안전하다). old path 가 노이즈든 아니든 new path 가 노이즈가 아니면 패널이
# 반드시 본다.
NOISE_RE='(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$|(^|/)node_modules/|(^|/)(dist|out|build)/'

# auto-PASS 자격이 있는 이미지/문서 자산 확장자.
ASSET_RE='\.(png|jpg|jpeg|gif|pdf)$'

jq -r \
  --arg state_re "$STATE_RE" \
  --arg noise_re "$NOISE_RE" \
  --arg asset_re "$ASSET_RE" '
  # 경로에 개행/제어문자가 있으면 재구성 diff 와 TSV 의 줄 구조를 깨뜨린다. git 은
  # 그런 경로를 허용하므로 무시하지 말고 fail-closed 로 잡는다.
  def ctl: test("[\\x00-\\x1f]");
  def paths: [.filename, (.previous_filename // empty)];

  [ .[]
    | . as $e
    | (paths) as $p
    | ($p | map(ascii_downcase)) as $lp
    | {
        f:      .filename,
        prev:   (.previous_filename // ""),
        status: .status,
        patch:  (.patch // ""),
        # API 는 바이너리 파일과 "diff 가 너무 큼" 두 경우 모두 patch 를 생략한다.
        # 패널이 읽을 텍스트가 없다는 점에서 둘 다 제외 대상이지만, auto-PASS 자격
        # (= 진짜 바이너리)은 changes==0 까지 요구한다.
        no_patch: (($e | has("patch")) | not),
        binary:   ((($e | has("patch")) | not) and ((.changes // 0) == 0)),
        # patch 가 없는데 changes>0 인 경우: git 은 바이너리가 아니라고 보지만(그러면
        # changes==0 일 것) API 가 diff 크기 때문에 patch 를 생략했다는 뜻 — 즉 패널이
        # 읽을 텍스트가 있는데 못 받는다. 이전 판은 이걸 "filtered" 로 접어 경고만 내고
        # 통과시켰다(리뷰 L3/L4 MAJOR — 혼합 PR 에서 큰 .tf/manifest 하나가 리뷰 없이
        # 사라진 채 PASS). 결정론적으로 잡을 죽인다.
        is_oversized: ((($e | has("patch")) | not) and ((.changes // 0) != 0)),
        deleted:  (.status == "removed"),
        bad_path: ($p | map(ctl) | any),
        is_state: ($lp | map(test($state_re)) | any),
        # new path(.filename) 단독 — old path 를 보면 rename 으로 우회 가능(위 주석).
        is_noise: (.filename | ascii_downcase | test($noise_re)),
        # rename 은 두 경로 **모두** 자산이어야 한다. 하나만 보면
        # `asset.png → payload.zip` 이 자격을 얻는다.
        is_asset: ($lp | map(test($asset_re)) | all)
      } ]
  | map(. + {
      # 분류. 순서가 의미를 갖는다: 경로 위생 → state → 대형 텍스트 → 읽을 수 없음/노이즈 → 패널.
      klass: (
        if .bad_path                then "badpath"
        elif .is_state and .deleted then "state_deleted"
        elif .is_state              then "state_fatal"
        elif .is_oversized          then "oversized_fatal"
        elif .no_patch or .is_noise then "filtered"
        else "panel" end)
    })
  | .[]
  | [ .klass, .f, .prev, .status,
      (if .binary then "1" else "0" end),
      (if .is_asset then "1" else "0" end) ]
  | @tsv
' "$FILES_JSON" > "$WORK/classified.tsv" || {
  echo "collect-diff.sh: jq classification failed on $FILES_JSON — refusing (fail-closed)" >&2
  exit 1
}

# ── panel.diff ────────────────────────────────────────────────────────────────
# patch 는 헝크만 담고 `diff --git` 헤더가 없으므로 헤더를 붙여 재구성한다. 여기서
# 만드는 헤더는 **다시 파싱되지 않는다** — 렌즈가 읽는 사람용 텍스트일 뿐이고, 판정은
# 전부 위의 JSON 필드로 이미 끝났다.
jq -r --arg state_re "$STATE_RE" --arg noise_re "$NOISE_RE" '
  def ctl: test("[\\x00-\\x1f]");
  def paths: [.filename, (.previous_filename // empty)];
  [ .[]
    | . as $e
    | (paths) as $p
    | ($p | map(ascii_downcase)) as $lp
    | select(($p | map(ctl) | any) | not)
    | select(($lp | map(test($state_re)) | any) | not)
    # new path 단독 — classified.tsv 의 is_noise 판정과 동일 기준(위 주석 참조).
    | select((.filename | ascii_downcase | test($noise_re)) | not)
    | select($e | has("patch"))
    | (.previous_filename // .filename) as $old
    | "diff --git a/\($old) b/\(.filename)"
      + (if (.previous_filename // "") != "" then "\nrename from \(.previous_filename)\nrename to \(.filename)" else "" end)
      + "\n--- " + (if .status == "added" then "/dev/null" else "a/\($old)" end)
      + "\n+++ " + (if .status == "removed" then "/dev/null" else "b/\(.filename)" end)
      + "\n" + .patch ]
  | join("\n")
  | if . == "" then empty else . end
' "$FILES_JSON" > "$WORK/panel.diff" || {
  echo "collect-diff.sh: jq panel.diff reconstruction failed — refusing (fail-closed)" >&2
  exit 1
}

# ── 경로 목록 ─────────────────────────────────────────────────────────────────
klass_paths() {  # $1=klass → 그 클래스의 경로(rename 의 old 포함), 정렬·중복제거
  awk -F'\t' -v k="$1" '$1 == k { print $2; if ($3 != "") print $3 }' \
    "$WORK/classified.tsv" | sort -u
}

klass_paths badpath        > "$WORK/fatal-badpath.txt"
klass_paths state_fatal    > "$WORK/fatal-state.txt"
klass_paths oversized_fatal > "$WORK/fatal-oversized.txt"
klass_paths state_deleted  > "$WORK/deleted-state.txt"
# filtered.txt 는 "패널에 전달되지 않은 경로" 전부다 — state 삭제도 포함한다. state-only
# 삭제 PR 은 panel.diff 가 비므로 auto-PASS 전제조건 ②(제외 경로가 존재한다)를 지나야
# 하는데, 여기서 빠지면 그 PR 이 영구 머지 불가로 돌아간다(ADR-004 §9 가 없애려던
# 실패 모드 그 자체).
{ klass_paths filtered; klass_paths state_deleted; } | sort -u > "$WORK/filtered.txt"
awk -F'\t' '{ print $2; if ($3 != "") print $3 }' "$WORK/classified.tsv" \
  | sort -u > "$WORK/all-paths.txt"

# auto-PASS 자격 박탈 목록. filtered klass 로 떨어진 파일 중 "git 기준 바이너리 ∧
# 삭제 ∧ 이미지/문서 자산"의 논리곱을 만족하지 않는 것 전부. `no_patch ∧ changes>0`
# (대형 텍스트)는 이미 위에서 oversized_fatal 로 갈라져 나가 잡을 죽이므로, 여기
# 도달하는 filtered 는 진짜 바이너리(binary=1, patch 없고 changes==0)나 텍스트지만
# noise 경로(binary=0, patch 있음) 뿐이다 — 후자는 아래 `$5 != "1"` 에서 그대로 걸린다.
# 남은 두 조건이 각각 다른 구멍을 막는다: 삭제가 아니면 rename 으로 allow-list 밖
# 경로를 들여올 수 있고, 자산이 아니면 컨테이너(zip/vsix/pptx)라 안에 무엇이 들었는지
# diff 로 알 수 없다.
# state 삭제(state_deleted)는 여기 들어가지 않는다 — 내용을 패널에 싣지 않는 대신
# 통과시키는 것이 base 에 추적된 state 를 지우는 위생 PR 의 유일한 해소 경로다
# (ADR-004 §9). 리포에 아무것도 들여오지 않으므로 삭제 조건의 근거가 그대로 성립한다.
awk -F'\t' '
  $1 != "filtered" { next }
  $5 != "1" { print $2; next }               # 텍스트(noise 경로) — 패널이 봤어야 했다
  $4 != "removed" { print $2; next }         # 삭제가 아님(추가·수정·rename)
  $6 != "1" { print $2 }                     # 바이너리지만 이미지/문서 자산 아님
' "$WORK/classified.tsv" | sort -u > "$WORK/unsafe-filtered.txt"

# `A || B && exit` 는 좌결합이라 의도대로 동작하지만(= `(A||B) && exit`), 그 함정이
# 이 리포의 ADR 에 이미 한 번 기록된 종류라 조건을 명시적으로 쓴다.
if [ -s "$WORK/fatal-badpath.txt" ] || [ -s "$WORK/fatal-state.txt" ] || [ -s "$WORK/fatal-oversized.txt" ]; then
  exit 2
fi
exit 0

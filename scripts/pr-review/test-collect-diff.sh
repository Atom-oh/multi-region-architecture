#!/usr/bin/env bash
# collect-diff.sh 의 실행 가능한 스펙. `bash scripts/pr-review/test-collect-diff.sh`.
#
# 여기서 검증하는 것은 전부 PR #34 리뷰가 지적한 실제 우회다 — rename 으로 state deny
# 를 빠져나가기, 인용 경로로 헤더 정규식을 빠져나가기, 자산 확장자를 단 텍스트 파일이
# 조용히 사라지기, base 에 추적된 state 삭제가 영구 차단되기.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0

run() {  # $1=name, $2=files.json(내용), 나머지는 assert 로 검사
  NAME="$1"; JSON="$2"
  TMP="$(mktemp -d)"; printf '%s' "$JSON" > "$TMP/files.json"
  bash "$DIR/collect-diff.sh" "$TMP/files.json" "$TMP/out" >/dev/null 2>&1
  RC=$?
  OUT="$TMP/out"
}

ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$NAME] $1" >&2; }

assert_rc()      { [ "$RC" = "$1" ] && ok || no "exit $RC != $1"; }
assert_has()     { grep -qxF "$2" "$OUT/$1" 2>/dev/null && ok || no "$1 missing '$2'"; }
assert_empty()   { [ ! -s "$OUT/$1" ] && ok || no "$1 should be empty, got: $(tr '\n' ' ' < "$OUT/$1")"; }
assert_grep()    { grep -qF "$2" "$OUT/$1" 2>/dev/null && ok || no "$1 missing text '$2'"; }
assert_nogrep()  { grep -qF "$2" "$OUT/$1" 2>/dev/null && no "$1 must NOT contain '$2'" || ok; }

# ── 1. rename 으로 state deny 우회 (리뷰 L3 CRITICAL) ─────────────────────────
# 헤더 파싱 판에서는 `diff --git a/prod.tfstate b/notes.txt` 의 어느 정규식 분기에도
# 걸리지 않았다. previous_filename 을 별도로 보면 걸린다.
run 'rename tfstate -> txt is fatal' '[
  {"filename":"notes.txt","previous_filename":"prod.tfstate","status":"renamed","changes":4,
   "patch":"@@ -1 +1 @@\n-password = hunter2\n+password = hunter2"}
]'
assert_rc 2
assert_has fatal-state.txt 'prod.tfstate'
# 그리고 헝크가 패널로 새어나가지 않아야 한다 — 이게 deny 의 실제 목적이다.
assert_nogrep panel.diff 'hunter2'

# ── 2. 인용이 필요한 경로 (리뷰 L3 CRITICAL) ──────────────────────────────────
# git diff 헤더라면 `diff --git "a/테스트.tfstate" ...` 로 인용돼 `^diff --git a/` 앵커를
# 빠져나갔다. JSON 값에는 인용이 없다.
run 'non-ASCII path is not exempt' '[
  {"filename":"테스트.tfstate","status":"modified","changes":2,
   "patch":"@@ -1 +1 @@\n-x\n+master_password = s3cret"}
]'
assert_rc 2
assert_has fatal-state.txt '테스트.tfstate'
assert_nogrep panel.diff 's3cret'

run 'path with a space is not exempt' '[
  {"filename":"my dir/a b.tfplan","status":"added","changes":1,"patch":"@@ -0,0 +1 @@\n+x"}
]'
assert_rc 2
assert_has fatal-state.txt 'my dir/a b.tfplan'

# ── 3. base 에 추적된 state 의 정리 경로 (리뷰 L2/L4 MAJOR) ───────────────────
# 삭제는 잡을 죽이지 않는다. 그러나 내용(= `-` 줄에 담긴 state 전문)은 패널로 가지
# 않는다. 그리고 filtered 에 올라 auto-PASS 전제조건 ② 를 만족한다.
run 'deleting a tracked state file is mergeable, content withheld' '[
  {"filename":"terraform/prod.tfstate","status":"removed","changes":900,
   "patch":"@@ -1,3 +0,0 @@\n-{\n-  \"master_password\": \"hunter2\"\n-}"}
]'
assert_rc 0
assert_has deleted-state.txt 'terraform/prod.tfstate'
assert_has filtered.txt 'terraform/prod.tfstate'
assert_empty fatal-state.txt
assert_empty unsafe-filtered.txt     # auto-PASS 자격 유지 → 머지 가능
assert_nogrep panel.diff 'hunter2'
assert_empty panel.diff

# ── 4. `\.tfplan` 무앵커 과차단 (리뷰 L2 MINOR) ───────────────────────────────
run 'notes.tfplan.md is a document, not a plan' '[
  {"filename":"docs/notes.tfplan.md","status":"modified","changes":2,
   "patch":"@@ -1 +1 @@\n-a\n+b"}
]'
assert_rc 0
assert_empty fatal-state.txt
assert_grep panel.diff 'docs/notes.tfplan.md'

# ── 5. plan.json 커버리지 갭 (리뷰 L2 MINOR) ──────────────────────────────────
run 'terraform show -json output is denied' '[
  {"filename":"tfplan.json","status":"added","changes":1,"patch":"@@ -0,0 +1 @@\n+{}"}
]'
assert_rc 2
assert_has fatal-state.txt 'tfplan.json'

# ── 6. 자산 확장자를 단 텍스트 파일 (리뷰 L3 MAJOR) ──────────────────────────
# 확장자 필터 판에서는 creds.png 가 텍스트여도 걸러져 어떤 렌즈에도 안 보였다. 이제
# 가시성은 확장자가 아니라 "API 가 patch 를 주는가"로 결정된다 → 패널이 본다.
run 'text file with an asset extension is reviewed, not dropped' '[
  {"filename":"creds.png","status":"added","changes":1,
   "patch":"@@ -0,0 +1 @@\n+aws_secret_access_key = AKIAIOSFODNN7EXAMPLE"},
  {"filename":"main.tf","status":"modified","changes":2,"patch":"@@ -1 +1 @@\n-a\n+b"}
]'
assert_rc 0
assert_grep panel.diff 'creds.png'
assert_grep panel.diff 'AKIAIOSFODNN7EXAMPLE'
assert_empty filtered.txt

# ── 7. 진짜 바이너리 자산 삭제만 있는 PR = auto-PASS 자격 (ADR-004 본론) ─────
# API 는 바이너리에 patch 를 주지 않고 changes 도 0 이다.
run 'binary asset deletions only -> auto-PASS eligible' '[
  {"filename":"qa/shot1.PNG","status":"removed","changes":0},
  {"filename":"docs/old.pdf","status":"removed","changes":0}
]'
assert_rc 0
assert_empty panel.diff
assert_has filtered.txt 'qa/shot1.PNG'
assert_empty unsafe-filtered.txt

# ── 8. rename 은 두 경로 모두 자산이어야 한다 ────────────────────────────────
run 'asset.png -> payload.zip rename loses eligibility' '[
  {"filename":"payload.zip","previous_filename":"asset.png","status":"renamed","changes":0}
]'
assert_rc 0
assert_has unsafe-filtered.txt 'payload.zip'   # 삭제가 아니므로 자격 박탈

# ── 9. lockfile-only PR 은 무심사 통과하지 못한다 (ADR-004 §5) ───────────────
run 'npm lockfile-only PR is not auto-PASS' '[
  {"filename":"src/frontend/package-lock.json","status":"modified","changes":40,
   "patch":"@@ -1 +1 @@\n-  \"integrity\": \"sha512-old\"\n+  \"integrity\": \"sha512-new\""}
]'
assert_rc 0
assert_empty panel.diff
assert_has unsafe-filtered.txt 'src/frontend/package-lock.json'

# ── 10. 제어문자 경로는 fail-closed ──────────────────────────────────────────
run 'control character in path is fatal' '[
  {"filename":"a\nb.tf","status":"added","changes":1,"patch":"@@ -0,0 +1 @@\n+x"}
]'
assert_rc 2
assert_grep fatal-badpath.txt 'b.tf'

# ── 11. 빈 입력은 거부 (fail-closed) ─────────────────────────────────────────
run 'empty files.json is refused' ''
assert_rc 1

# ── 12. .terraform.lock.hcl 은 패널이 본다 (ADR-004 §5) ──────────────────────
run 'terraform lockfile reaches the panel' '[
  {"filename":"terraform/environments/production/us-east-1/.terraform.lock.hcl",
   "status":"modified","changes":6,"patch":"@@ -1 +1 @@\n-h1:old\n+h1:new"}
]'
assert_rc 0
assert_grep panel.diff '.terraform.lock.hcl'
assert_empty filtered.txt

echo "collect-diff: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

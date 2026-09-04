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

# ── 8. rename 은 auto-PASS 자격을 얻지 못한다 ────────────────────────────────
# 무변경 rename 은 이제 header-only 헝크로 패널에 보인다(M-L4-2) — filtered 로 접히지
# 않으므로 unsafe-filtered 가 아니라 panel.diff 비어있지 않음이 auto-PASS 를 막는다.
run 'asset.png -> payload.zip rename is visible to the panel, not auto-PASS' '[
  {"filename":"payload.zip","previous_filename":"asset.png","status":"renamed","changes":0}
]'
assert_rc 0
assert_grep panel.diff 'rename from asset.png'
assert_grep panel.diff 'rename to payload.zip'
assert_empty filtered.txt

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

# ── 13. rename 으로 노이즈 필터 우회 (PR#34 리뷰 L3 CRITICAL) ────────────────
# old path 만 노이즈여도 `any` 로 제외하면, 노이즈 경로에서 실제 IaC 로 rename 한
# 실변경이 패널에서 사라진다. new path(terraform/waf.tf) 는 노이즈가 아니므로 반드시
# 패널이 봐야 한다.
run 'rename FROM a noisy lockfile is still reviewed' '[
  {"filename":"terraform/waf.tf","previous_filename":"package-lock.json",
   "status":"renamed","changes":3,
   "patch":"@@ -1 +1 @@\n-old_rule\n+new_waf_rule = \"0.0.0.0/0\""}
]'
assert_rc 0
assert_grep panel.diff 'terraform/waf.tf'
assert_grep panel.diff 'new_waf_rule'
assert_empty filtered.txt

# rename TO a noisy path is ALSO reviewed (round-2 리뷰 M-L4-1 — round-8 수정의
# 거울상): 실제 IaC 파일을 노이즈 경로로 rename 하면 경고 하나만 남기고 변경이
# 사라졌다. is_noise 는 두 경로 **모두** 노이즈일 때만 제외한다.
run 'rename TO a noisy lockfile is still reviewed' '[
  {"filename":"package-lock.json","previous_filename":"terraform/waf.tf",
   "status":"renamed","changes":3,"patch":"@@ -1 +1 @@\n-a\n+b"}
]'
assert_rc 0
assert_grep panel.diff 'terraform/waf.tf'
assert_empty filtered.txt

# 두 경로 모두 노이즈인 rename 만 제외된다.
run 'noise-to-noise rename is filtered' '[
  {"filename":"pnpm-lock.yaml","previous_filename":"yarn.lock",
   "status":"renamed","changes":3,"patch":"@@ -1 +1 @@\n-a\n+b"}
]'
assert_rc 0
assert_has filtered.txt 'pnpm-lock.yaml'
assert_empty panel.diff

# ── 14. no_patch ∧ changes>0 은 fail-closed (PR#34 리뷰 L3/L4 MAJOR) ─────────
# API 가 diff 가 너무 커서 patch 를 생략한 텍스트 파일(진짜 바이너리와 달리 changes>0).
# 이전 판은 filtered+경고만 내고 통과시켜, 혼합 PR 에서 이 파일만 리뷰 없이 사라진 채
# 나머지가 PASS 됐다.
run 'oversized text diff without a patch is fatal, not filtered' '[
  {"filename":"terraform/huge.tf","status":"modified","changes":50000}
]'
assert_rc 2
assert_has fatal-oversized.txt 'terraform/huge.tf'
assert_empty filtered.txt

# 진짜 바이너리(changes==0)는 여전히 filtered 로 남아 auto-PASS 경로를 막지 않는다.
run 'real binary (changes=0, no patch) is still just filtered' '[
  {"filename":"logo.png","status":"modified","changes":0}
]'
assert_rc 0
assert_has filtered.txt 'logo.png'
assert_empty fatal-oversized.txt

# ── 15. STATE_RE 변형 커버리지 (round-2 리뷰 M-L2-1) ─────────────────────────
# `terraform state pull`/`show -json`/`-out=` 의 흔한 산출물 이름들이 어느 분기에도
# 안 걸려 텍스트 전문이 패널 전 셀로 나갔다.
for f in 'terraform.tfstate.json' 'envs/prod/state.json' 'prod-plan.json' 'prod.plan' 'prod.tfplan.json'; do
  run "state/plan variant $f is denied" '[
    {"filename":"'"$f"'","status":"added","changes":1,"patch":"@@ -0,0 +1 @@\n+{\"master_password\":\"hunter2\"}"}
  ]'
  assert_rc 2
  assert_has fatal-state.txt "$f"
  assert_nogrep panel.diff 'hunter2'
done
# 과차단 회귀 방지: 계획/상태와 무관한 흔한 이름은 여전히 리뷰된다.
run 'app deployment-plan.md is not a terraform plan' '[
  {"filename":"docs/deployment-plan.md","status":"modified","changes":2,"patch":"@@ -1 +1 @@\n-a\n+b"}
]'
assert_rc 0
assert_empty fatal-state.txt
assert_grep panel.diff 'docs/deployment-plan.md'

# ── 16. 무변경 rename 가시화 (round-2 리뷰 M-L4-2) ───────────────────────────
# Terraform 모듈 디렉터리 git mv = state address 이동(destroy/recreate 경로)인데,
# patch 없음 ∧ changes==0 을 "binary" 로 접으면 어떤 렌즈에도 안 보였다.
run 'zero-change terraform rename reaches the panel as a header-only hunk' '[
  {"filename":"terraform/modules/vpc-v2/main.tf","previous_filename":"terraform/modules/vpc/main.tf",
   "status":"renamed","changes":0}
]'
assert_rc 0
assert_grep panel.diff 'rename from terraform/modules/vpc/main.tf'
assert_grep panel.diff 'rename to terraform/modules/vpc-v2/main.tf'
assert_empty filtered.txt

# ── 17. 알려진 한계의 기록: removed+added 분해 (round-2 리뷰 M-L3-3) ─────────
# rename status 는 GitHub 의 유사도 탐지가 결정한다 — state 파일을 크게 수정하며
# 이동하면 API 는 removed(옛 state 이름) + added(비-state 새 이름, patch 전문) 두
# 엔트리로 보고하고, added 쪽은 STATE_RE 를 지나 패널로 간다. 경로 기반 deny 는 임의
# 파일명에 내용을 붙여넣는 경우를 원리적으로 못 잡는다(ADR-004 의 시크릿 스캐너
# 후속이 다루는 축). 이 테스트는 그 한계가 "여기까지"임을 고정한다: removed 쪽은
# 여전히 state_deleted 로 잡히고, 한계가 조용히 넓어지면(removed 쪽마저 새면) 깨진다.
run 'KNOWN LIMIT: state moved via removed+added — added side reaches the panel' '[
  {"filename":"terraform/prod.tfstate","status":"removed","changes":900,
   "patch":"@@ -1,3 +0,0 @@\n-{\n-  \"master_password\": \"hunter2\"\n-}"},
  {"filename":"notes/archive.txt","status":"added","changes":900,
   "patch":"@@ -0,0 +1,3 @@\n+{\n+  \"master_password\": \"hunter2\"\n+}"}
]'
assert_rc 0
assert_has deleted-state.txt 'terraform/prod.tfstate'
assert_grep panel.diff 'notes/archive.txt'   # 문서화된 한계 — 패널이 보긴 한다(사람 눈)

# ── 18. round-3 리뷰: oversized 의 삭제 예외 + noise 우선 + lockfile 후순위 ───
# 대형 텍스트 파일의 삭제는 쪼갤 수 없으므로 fatal 이 아니라 filtered + auto-PASS
# 자격 박탈이다.
run 'oversized DELETION is not fatal but revokes auto-PASS' '[
  {"filename":"generated/huge-manifest.yaml","status":"removed","changes":50000}
]'
assert_rc 0
assert_empty fatal-oversized.txt
assert_has filtered.txt 'generated/huge-manifest.yaml'
assert_has unsafe-filtered.txt 'generated/huge-manifest.yaml'

# patch 가 생략될 만큼 큰 lockfile 은 어떤 렌즈도 안 읽을 파일 — 잡을 죽이면 안 된다.
run 'oversized lockfile is noise, not fatal' '[
  {"filename":"src/frontend/package-lock.json","status":"modified","changes":50000},
  {"filename":"main.tf","status":"modified","changes":2,"patch":"@@ -1 +1 @@\n-a\n+b"}
]'
assert_rc 0
assert_empty fatal-oversized.txt
assert_has filtered.txt 'src/frontend/package-lock.json'
assert_grep panel.diff 'main.tf'

# .terraform.lock.hcl 은 panel.diff 의 맨 뒤로 정렬된다 — 전역 절단(head -3000)이
# .tf 실변경보다 해시를 먼저 잘라내도록.
run 'lockfile hunks sort to the END of panel.diff' '[
  {"filename":"terraform/environments/production/us-east-1/.terraform.lock.hcl",
   "status":"modified","changes":6,"patch":"@@ -1 +1 @@\n-h1:old\n+h1:new"},
  {"filename":"terraform/environments/production/us-west-2/main.tf",
   "status":"modified","changes":2,"patch":"@@ -1 +1 @@\n-a\n+b_westtf_change"}
]'
assert_rc 0
TF_LINE="$(grep -n 'b_westtf_change' "$OUT/panel.diff" | cut -d: -f1)"
LOCK_LINE="$(grep -n 'h1:new' "$OUT/panel.diff" | cut -d: -f1)"
if [ -n "$TF_LINE" ] && [ -n "$LOCK_LINE" ] && [ "$TF_LINE" -lt "$LOCK_LINE" ]; then ok; else no "lockfile hunk not sorted after .tf hunk (tf=$TF_LINE lock=$LOCK_LINE)"; fi

echo "collect-diff: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

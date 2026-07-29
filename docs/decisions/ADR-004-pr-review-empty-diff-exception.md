# ADR-004: PR-review 게이트의 diff 수집 — 삭제 전용 PR 의 단일 예외와 state/plan deny

## Status

Accepted (2026-07-28).

번호에 대해: 이 브랜치만 보면 003 이 빠진 것처럼 보이지만,
`ADR-003-eks-mgmt-ownership-handoff.md`는 먼저 머지되는 PR #22 가 추가한다. 두 PR 이
같은 창에서 열려 번호를 나눠 쓴 것이고, 머지 후 순서는 연속이다.

## Context

`.github/workflows/pr-review.yml`의 설계 불변식은 **fail-closed**다: 의장이
`VERDICT: PASS`를 마지막 줄에 정확히 한 번 출력하지 않으면 게이트가 막는다. 패널이
죽어도, 타임아웃이 나도, VERDICT가 없어도 막힌다. 이건 의도된 것이다 — 리뷰가 돌지
않았는데 통과하는 것보다 막히는 게 낫다.

그런데 이 불변식에 리뷰 대상이 애초에 없는 구멍이 있었다. "Get PR diff" 스텝은 패널이
읽어도 의미가 없는 파일을 awk로 걷어낸다(바이너리, 이미지, 의존성 락파일, 빌드
산출물). 그 필터를 통과하는 텍스트가 **한 줄도 남지 않는** PR — 실제 사례: 리포지토리
루트에 쌓인 QA 스크린샷 PNG 16개를 지우는 PR #23 — 은 0바이트 diff가 되고
`scripts/pr-review/run-panel.sh`가 fail-close 한다:

```
run-panel.sh: $DIFF is empty (0 bytes) — refusing to run a panel with no diff to review
```

패널이 죽으면 VERDICT가 없고, 게이트도 fail-close 한다. 결과는 **아무 지적도 없이 영구히
머지 불가인 PR**이다. 이건 fail-closed가 보호하려던 상황(리뷰 없이 통과)이 아니라, 게이트
자체의 논리 공백이다. admin merge로 우회할 수는 있지만, 통제를 우회하는 습관을 만드는
쪽이 통제를 고치는 쪽보다 나쁘다.

## Decision

이 ADR 은 세 가지를 결정한다. **(D1)** 분류와 패널 diff 를 `gh pr diff` 텍스트가 아니라
`pulls/{n}/files` **JSON** 에서 만든다. **(D2)** 삭제 전용 PR 에 한해 패널을 건너뛰고
PASS 한다 — fail-closed 정책의 **유일한** 예외. **(D3)** Terraform state/plan 산출물의
추가·수정·rename 은 결정론적으로 잡을 죽이고, 삭제는 내용을 전달하지 않은 채 통과시킨다.

### D1. diff 헤더를 파싱하지 않는다

경로 판정의 입력은 `scripts/pr-review/collect-diff.sh` 가 읽는
`gh api repos/{owner}/{repo}/pulls/{n}/files` 의 JSON 이다. 이전 판은 `diff --git` 헤더
문자열에서 경로를 뽑았고, 그 자리에 fail-open 이 두 개 있었다:

- **rename**: `git mv a.tfstate y.txt` → `diff --git a/a.tfstate b/y.txt`. old 경로 뒤에
  오는 것은 줄끝이 아니라 **공백**이라 `\.tfstate($|\.|[0-9])` 의 세 분기 전부 실패하고,
  new 경로는 `.txt` 라 애초에 안 걸린다. state deny 가 조용히 통과하고 헝크(= 평문
  자격증명)가 16셀 전부로 나간다.
- **인용 경로**: git 은 비-ASCII·공백 경로를 `diff --git "a/..." "b/..."` 로 인용한다.
  `^diff --git a/` 앵커가 `"a/` 에 매치되지 않아 그 경로는 **모든** 검사에서 투명해진다.

두 구멍의 뿌리는 같다: diff 헤더는 경로의 신뢰할 수 있는 표현이 아니다. 그래서 헤더를
더 정교하게 파싱하는 대신 파싱을 없앤다. files API 는 `filename` /
`previous_filename` / `status` / `patch` 를 JSON 값으로 준다 — 인용 없음, 헤더 없음,
rename 의 두 경로가 별도 필드. 패널 diff 는 그 목록에서 **고른** 파일의 `patch` 로
재구성하므로, "제외했는데 헝크는 새어나갔다"가 구조적으로 불가능해진다. 부수 효과로
`patch` 유무가 곧 "패널이 읽을 텍스트가 있는가"이므로, 확장자 allow-list 로 파일을
걷어내던 필터가 사라진다 — 자산 확장자를 단 텍스트 파일이 렌즈에서 사라지는 문제가
같이 닫힌다.

경로 열거의 완전성도 이 결정에 딸려 있다: `--paginate` 없이는 기본 30개만 보므로
31번째 파일의 state 가 검출되지 않고, files API 자체가 PR 당 3000 파일에서 잘리므로
파일 수가 3000 이상이면 분류가 완전할 수 없어 잡을 죽인다.

각 우회와 각 경계 조건은 `scripts/pr-review/test-collect-diff.sh` 에 실행 가능한
케이스로 있다 — `pull_request_target` 은 base-ref 의 워크플로를 실행하므로 이 로직의
회귀는 브랜치 CI 로 드러나지 않는다(경계 조건 8번과 같은 이유). 이 파일들을 고치면
그 테스트를 같이 고친다.

### D2. 삭제 전용 PR 의 auto-PASS

**변경 전체가 (a) 패널이 읽을 수 없거나 노이즈여서 필터에 걸리고 (b) **삭제**이며
(c) 이미지/문서 자산(git 기준 바이너리 ∧ `png|jpg|jpeg|gif|pdf`)이거나 state/plan 이고
(d) 리뷰 가능한 텍스트가 0줄로 남은 PR만, 패널을 건너뛰고 `VERDICT: PASS`를 기록한다.**

핵심은 **판정 근거를 PR 작성자가 통제할 수 없는 값에 두는 것**이다. "필터가 전부
걷어냈다"만을 조건으로 삼으면, 스킵 목록에 경로가 걸리기만 하는 *텍스트* 파일 —
이 리포에 실제로 3개 있는 `package-lock.json`(`src/frontend/`, `scripts/seed-data/`,
`webpage/`) — 만 바꾸는 PR 이 무심사 통과한다. `resolved` URL 과 `integrity` 해시만
갈아끼우는 공급망 PR 이 정확히 그 형태다. 그래서 auto-PASS 자격은 경로 패턴이 아니라
git 이 그 blob 을 바이너리로 판정했는지에 걸려 있다(files API 가 `patch` 를 생략하고
`changes == 0` 인 경우).

전제조건 (셋 다 만족해야 하며, 하나라도 깨지면 기존대로 fail-close):

1. **PR 이 실제로 파일을 건드렸다** (`[ -s .../all-paths.txt ]`). 안 건드렸다면
   files API 이상 상황이지 "전부 필터됨"이 아니다. 그런데도 PASS 하면 코멘트가
   사실과 다른 근거("전부 패널 필터 대상")를 달고 제외 경로 목록은 빈 채로 게시된다.

2. **패널에 전달되지 않은 경로가 실제로 존재한다** (`[ -s .../filtered.txt ]`).
   1번과 함께, 예외의 서술과 실제 상태가 어긋나는 경우를 배제한다.

3. **제외된 것 전부가 auto-PASS 자격이 있다** (`[ ! -s .../unsafe-filtered.txt ]`) —
   git 기준 바이너리 ∧ 삭제 ∧ 이미지/문서 자산, 또는 state/plan 삭제(9번).
   각 항목이 다른 구멍을 막는다.

   - **바이너리** — files API 가 `patch` 를 생략하고 `changes == 0` 인 것으로 판정한다.
     확장자 추측이 아니라 git 자신의 판정이다. 텍스트라면 패널이 읽을 수 있으니
     읽혀야 한다. (`patch` 는 없지만 `changes != 0` 이면 "diff 가 너무 큼"이지 바이너리가
     아니다 — 패널에 전달할 텍스트는 없으나 auto-PASS 자격도 없다.)
   - **삭제** (`status == "removed"`) — 이게 rename 우회를 닫는다.
     `asset.png → payload.zip` 형태의 rename+modify 는 new 경로가 allow-list 밖이므로
     이 조건 없이는 저장소에 `payload.zip` 을 남기면서 자격을 얻는다 — 즉 이 예외의
     불변식("변경 전체가 자산")이 깨진다. D1 이후로는 두 경로가 별도 필드라 rename 을
     경로 수준에서도 잡지만, 삭제 조건은 그와 독립적으로 계열 전체를 닫는다: 삭제되는
     blob 은 리포에 아무것도 들여오지 않으므로 컨테이너 안의 내용도 스크린샷에 찍힌
     시크릿도 무심사 통과의 위험이 되지 않는다. 이 예외가 해소하려던 실제 사례(스크린샷
     정리 PR)는 정의상 전부 삭제이므로, 대상은 좁아지지 않는다.
   - **이미지/문서 자산 확장자** (`png|jpg|jpeg|gif|pdf`, `ascii_downcase` 후 매칭 —
     `.PNG` 도 후보다) — 삭제 조건이 이미 대부분을 덮지만,
     "무심사 통과 가능"의 표면을 최소로 유지한다. `pptx` 는 이전 판에서 allow-list 에
     있었는데 제거했다: `zip`/`vsix` 를 컨테이너라는 이유로 제외하면서 같은 OOXML
     ZIP 컨테이너인 pptx 를 허용하는 것은 같은 기준의 자기모순이다. 컨테이너는
     패널을 태운다. `pdf` 는 남겼다 — 그것도 구조화 컨테이너지만, 삭제 조건 아래에서는
     안에 무엇이 들었는지가 무관해진다(리포에 들어오지 않는다). 즉 컨테이너 기준을
     적용하는 축은 "무엇이 들어오는가"이고, pptx 제거는 그 기준의 적용이 아니라
     **표면 최소화**다: 리포에 pptx 삭제 PR 이 실제로 없다.

### D3. Terraform state/plan 산출물

**추가·수정·rename 은 결정론적으로 잡을 죽인다. 삭제는 통과시키되 그 내용은 패널에
전달하지 않는다.** 상세와 기각한 대안은 아래 9번.

경계 조건:

4. **판정 근거는 실제로 패널에 전달할 파일이다.** `total_lines`(GITHUB_ENV로 넘어온 값)를
   믿지 않고 `/tmp/pr-diff-truncated.txt`를 `[ -s ]`로 직접 본다 —
   `run-panel.sh`의 "0 bytes" 기준과 일치시킨 것이다. 넘겨받은 변수에 의존하면, 스텝
   재배치로 그 변수가 사라졌을 때 `${var:-0}`이 조용히 0으로 접혀 *모든* PR 을
   auto-PASS 시키는 단일 실패점이 생긴다. 그 안티패턴을 피하려고 파일을 직접 읽는다.

5. **`.terraform.lock.hcl`은 필터에서 제외하지 않는다.** provider 버전과 무결성 해시를
   고정하는 파일이고, IaC 리포에서 리뷰할 가치가 있는 사실상 유일한 공급망 표면이며,
   무엇보다 **읽을 수 있는 텍스트**다. 이 결정 이전에는 필터에 있었고, 그 상태로 예외를
   도입하면 `.terraform.lock.hcl`만 바꾸는 PR이 무심사 통과했을 것이다. npm 계열
   락파일은 노이즈 목록에 남아 있고, 전제조건 3번이 그것들만 바뀐 PR 의 auto-PASS 를 막는다
   (텍스트이므로 `unsafe` 로 분류된다). 다만 이것은 필터에서 빼는 것과 **같지 않다**.
   실제 동작은 이렇다: (a) 텍스트가 섞인 PR 에서 npm lockfile 의 `resolved`/`integrity`
   교체는 여전히 어떤 렌즈에도 노출되지 않는다 — 리뷰 커버리지는 복구되지 않는다.
   (b) npm lockfile **만** 바꾸는 PR 은 전제조건 3번에 걸려 fail-close 하므로, 이 ADR 이
   해소하려던 "영구 머지 불가"가 그 종류의 PR 에 대해서는 그대로 남는다(admin merge
   필요). 막은 것은 무심사 통과뿐이고, 그 대가로 얻는 것은 패널의 3000줄 예산을
   lockfile 해시로 잠식하지 않는 것이다. 두 쪽을 다 원하면 npm lockfile 을 필터에서
   빼고 파일당 줄 상한을 도입하는 게 맞는 방향이지만, 이 ADR 의 범위 밖이다.

6. **스킵은 눈에 보이게 한다.** 코멘트에 패널로 가지 않은 경로 목록을 그대로 싣고
   (백틱은 `&#96;`로 이스케이프 — 파일명으로 마크다운을 주입하지 못하게),
   `panel_responded=skipped (...)`, `chair_used=no chair — panel skipped`를 설정해
   의장이 실행된 것처럼 보이지 않게 한다. 전제조건이 깨져 fail-close 할 때는
   어느 **전제조건 번호**가 깨졌는지, 그리고 어느 경로가 자격을 박탈했는지
   `::error::`로 각각 남긴다. `unsafe-filtered` 는 auto-PASS 분기 안에서만 계산되지
   않고 **항상** 계산되므로, 텍스트가 섞인 혼합 PR 에서도 `::warning::` 으로 남는다.

7. **필터 목록과 예외 범위는 커플링되어 있다.** `collect-diff.sh` 의 `NOISE_RE` 나
   `ASSET_RE` 에 경로·확장자를 추가하면 auto-PASS 후보가 함께 넓어진다(전제조건 3번이
   걸러주지만, 새 바이너리 확장자를 `ASSET_RE` 에 넣는 경우는 걸러지지 않는다).
   목록을 건드릴 때 이 ADR 과 `test-collect-diff.sh` 를 같이 갱신한다. 두 정규식 옆과
   파일 상단 주석에 그 요구를 남겼다.

8. **셸에 인라인된 awk/jq 프로그램 안에 아포스트로피를 쓰지 않는다.** 셸에서 단일
   인용으로 감싸여 있어서, 주석 안의 `panel's` 하나가 인용을 닫고 스텝을 셸 구문 오류로
   죽인다. `pull_request_target` 은 base-ref 의 워크플로 파일을 실행하므로 이 종류의
   실수는 브랜치에서 CI 로 드러나지 않는다 — 머지된 뒤에 드러난다. 이 PR 을 오프라인
   하네스로 검증하다가 실제로 하나 잡았다. 로직이 스크립트 파일로 옮겨간 뒤에도
   `collect-diff.sh` 안의 jq 프로그램에 같은 제약이 그대로 적용된다.

9. **Terraform state/plan: 추가·수정·rename 은 즉시 실패, 삭제는 내용 없이 통과.**
   처음에는 `*.tfstate`/`*.tfplan` 를 스킵 목록에 넣었는데, 그게 최악의 조합이었다.
   두 가지 이유로 그렇다.
   - **혼합 PR 에서 조용히 사라진다.** unsafe 분류 검사가 `[ ! -s ...truncated ]`
     블록 안에서만 돌았기 때문에, `.tf` 변경과 state 가 함께 커밋된 PR 은 그 검사에
     아예 도달하지 않았다. state 만 필터에 먹히고 패널은 나머지를 리뷰하며,
     `::error::` 도 없다. 스킵 이전에는 최소한 렌즈에 노출되었으니 순수한 회귀다.
   - **state-only 정리 PR 이 새 영구 머지 불가가 된다.** state 는 git 기준 텍스트라
     unsafe 로 분류되어 fail-close 한다 — 하필 위생상 가장 장려해야 할 PR 종류에,
     이 ADR 이 없애려던 실패 모드가 재생성된다.

   프롬프트에 싣는 것도 답이 아니다: Aurora/DocumentDB master password 가 평문으로
   들어 있고, 그게 4모델×4렌즈로 외부 provider 에 나간다.

   그래서 **추가·수정·rename** 은 `::error::` + `exit 1` 이다. 검출은 diff 구성과
   무관하다 — files API 의 `filename` 과 `previous_filename` 을 각각 검사하므로
   (D1) rename 도 인용 경로도 우회가 아니다. 패턴은 `*.tfstate`, `*.tfstate.<n>`,
   `*.tfstate.backup`, `*.tfplan`, 확장자 없는 `tfplan`/`plan.out`,
   `terraform.tfstate.d/`, 그리고 `plan.json`/`tfplan.json`(`terraform show -json`
   산출물 — state 와 같은 평문 자격증명을 담는다) 을 덮는다. `\.tfplan` 은 경로
   세그먼트에 앵커한다 — 무앵커였을 때 `docs/notes.tfplan.md` 같은 **문서**가 잡을
   죽였다. 해소 경로는 브랜치에서 그 커밋을 되돌리는 것이며(그리고 노출된 자격증명
   회전), 에러 메시지가 그 절차를 지시한다.

   **삭제는 다르다.** base 에 이미 추적된 state 를 `git rm` 하는 위생 PR 도
   추가·수정과 같이 취급하면 그 PR 이 영구 머지 불가가 되고, 에러 메시지가 지시하는
   해소책("브랜치에서 제거")의 결과물이 같은 검사에 다시 걸린다 — 위 두 번째 이유를
   그대로 재생산하는 것이다. 그래서 삭제는 통과시킨다. 단순히 통과시키는 게 아니다:
   텍스트 파일의 삭제 diff 는 파일 전문을 `-` 줄로 담으므로, 통과시키면서 패널에
   실으면 이 deny 가 막으려던 바로 그것(평문 자격증명의 외부 모델 전송)이 일어난다.
   `collect-diff.sh` 는 그 파일의 `patch` 를 `panel.diff` 에 **아예 넣지 않는다** —
   패널 diff 는 헝크를 걷어내는 게 아니라 고른 파일로 재구성되는 것이므로(D1), 경로만
   남고 내용은 어떤 출력 파일에도 실리지 않는다. 워크플로는 `::warning::` 으로 삭제된
   경로를 나열하고 자격증명 회전을 지시한다. 삭제만 있는 PR 은 `panel.diff` 가 비므로
   D2 의 auto-PASS 로 흘러간다 — `filtered.txt` 에 그 경로들이 올라 전제조건 ② 를
   만족하고, `unsafe-filtered.txt` 에는 들어가지 않는다(리포에 아무것도 들여오지
   않으므로 삭제 조건의 근거가 그대로 성립한다).

## Consequences

**얻는 것**

- **바이너리 자산 삭제 PR 과 state 정리 PR** — 게이트를 우회(admin merge)해야만 머지되던
  두 종류가 정상 경로로 통과한다. 통제 우회를 정상 절차로 만들지 않는다. 다른 종류(예:
  npm lockfile-only PR — 5번)는 여전히 남는다.
- 경로 판정에서 rename·인용 경로 fail-open 이 닫힌다(D1). 같은 뿌리에서 나오던
  "확장자 allow-list 때문에 텍스트 파일이 모든 렌즈에서 사라진다"도 함께 닫힌다 —
  가시성이 확장자가 아니라 `patch` 유무로 결정되기 때문이다.
- `.terraform.lock.hcl`이 리뷰 대상으로 승격된다 — 예외를 도입하려고 살펴본 덕에 발견한,
  이전부터 있던 공백이다.

**받아들이는 리스크**

- **이미지·문서 자산 전용 PR 에 대한 심사가 없다.** 패널은 원래 이런 파일을 읽지 못했으니
  *패널* 커버리지가 줄지는 않지만, 결과가 "머지 불가" → "무심사 머지 가능"으로 바뀌므로
  실효 통제는 분명히 약해진다. 그게 이 ADR 이 감수하는 것이다. PNG 에 시크릿이나 악성
  페이로드를 심는 경로는 이 게이트가 전에도 잡지 못했고 지금도 못 잡는다.
  맞는 보완은 이 예외를 되돌리는 것이 아니라 시크릿 스캐너를 **게이트 전체에** 별도
  결정론적 잡으로 붙이는 것이다(auto-PASS 경로만이 아니라 — 텍스트 PR 도 지금 스캔되지
  않는다). 이 ADR 의 범위 밖으로 두고 후속 작업으로 남긴다.
- **state 삭제 PR 도 무심사 통과한다.** 삭제된 state 의 내용은 어떤 렌즈도 보지 않으므로
  "그 커밋이 정말 삭제만 하는가"를 검증하는 것은 files API 의 `status` 필드뿐이다.
  같은 PR 에 텍스트 변경이 섞여 있으면 그쪽은 정상적으로 리뷰되므로, 무심사가 되는 것은
  삭제만 있는 PR 에 한정된다. 자격증명 회전은 `::warning::` 이 지시하지만 강제하지 않는다.
- 노이즈 목록이나 자산 확장자 allow-list 가 넓어질 때 auto-PASS 범위가 조용히 넓어질 수
  있다 — 위 7번이 그에 대한 방어이며, 사람의 규율에 의존한다.
- npm lockfile-only PR 은 여전히 fail-close 로 남는다(5번).
- state/plan 의 **추가·수정·rename** 은 패널·의장·예외 판정 이전에 잡을 죽인다. 브랜치에서
  커밋을 되돌리는 것 외에 통과 경로가 없다 — admin merge 로도 게이트 실패는 남는다.
  이건 의도된 것이다.
- **provider 범프 PR 이 절단될 수 있다.** `.terraform.lock.hcl` 승격 × 리전 수만큼의
  fan-out 이면 lock 파일 해시 수백 줄이 `head -3000` 예산을 잠식해 뒤따르는 `.tf` 변경이
  절단될 수 있다. 절단 자체는 이전에도 있던 동작이고 절단 사실은 코멘트에 배너로
  표시되지만, 이 ADR 이 발생 확률을 올린다. 파일당 줄 캡은 후속 작업으로 남긴다.

## References

- `scripts/pr-review/collect-diff.sh` — 분류 + 패널 diff 재구성(D1·D2·D3 의 구현 전체).
  정규식(`STATE_RE`/`NOISE_RE`/`ASSET_RE`)과 분류 순서가 여기 한 곳에 있다.
- `scripts/pr-review/test-collect-diff.sh` — 위 파일의 실행 가능한 스펙. rename·인용
  경로·자산 확장자 텍스트 파일·base-추적 state 삭제 등 각 우회가 케이스로 있다.
- `.github/workflows/pr-review.yml` — "Get PR diff"(files API 페치 + collect-diff 호출 +
  state 삭제 경고), "Build lens prompts"(`head -3000` 절단 — 판정 대상 파일이 여기서
  생성된다), "Run panel + synthesize"(전제조건 검사 + auto-PASS)
- `scripts/pr-review/run-panel.sh` — 빈 diff fail-close 지점(`-s` 기준의 근거)
- `scripts/pr-review/synthesize.sh` — 의장 실행. `CHAIR_MAX_TURNS`(기본 8,
  fallback 12)와 `CHAIR_ALLOWED_TOOLS`(**기본 빈 값 = 플래그 미전달**)가 여기 있다. 턴 캡의 근거는
  PR #34 에서 관측된 실패다: 16/16 셀이 응답했는데도 primary·fallback 둘 다 600s 벽시계
  캡을 종합이 아닌 리포 탐색 루프에 다 쓰고 빈 결과를 냈다. 로컬 재현에서 같은 입력이
  `--max-turns 8` 로 2분 23초에 VERDICT 까지 정상 완료했다. fallback 에 더 큰 예산을 주는
  이유: fallback 은 primary 가 캡을 소진해서 불려오는 경우가 가장 흔하고, 같은 캡이면
  같은 벽에 부딪힌다.

  `--allowedTools` 는 **의도적으로 기본 비활성**이다. 의장의 stdin 은 PR 작성자가 통제하는
  텍스트이고 이 잡은 `pull_request_target` 컨텍스트라 툴을 read/grep/glob 로 좁히는 게
  옳은 방향이지만, 러너에서 회귀했다: 같은 PR 에서 `--max-turns 8` 만 준 실행(`2cab1c6`)은
  531s 에 10242 바이트로 정상 종합했는데, 거기에 `--allowedTools Read,Grep,Glob` 만 더한
  실행(`b213da3`)은 primary·fallback 둘 다 600s 를 다 쓰고 16 바이트(`Execution error`)를
  냈다. 로컬 `claude` 2.1.220 은 같은 플래그를 정상 처리하므로 러너 이미지의 CLI 판본
  차이로 본다(비대화형 `-p` 에서 권한 요청이 매달리는 형태). 기본을 비우면 이 PR 이전과
  동작이 같으므로 새 위험을 들이는 게 아니라 개선을 유보하는 것이고, 잔여 위험은
  ADR-002 와 동일하게 `lib.sh::scrub_secrets` 가 마지막 방어선으로 받는다. 러너 이미지의
  `claude --version` 을 확인한 뒤 `CHAIR_ALLOWED_TOOLS` 를 세팅해 되살린다.

  같은 실패가 진단 불가였던 것 자체도 고쳤다: 의장의 stderr 는 `chair.err` 에만 있고
  워크플로 로그에는 없었으며(원인 추적을 실행 이력 대조로 해야 했다), "둘 다 실패"
  메시지가 `[ ! -s "$OUT" ]` 즉 **빈 파일**만 봤기 때문에 `Execution error` 16 바이트는
  그 분기를 지나쳐 **PR 코멘트 본문 전체**로 게시됐다. 이제 저하 시 stderr 를
  `::group::` 으로 스크럽해 남기고, 본문 판정 기준을 `chair_degraded` 로 맞춰 원인과
  의장의 원 출력 앞 500B 를 코멘트에 쓴다.
- `docs/decisions/ADR-002-pr-review-kiro-fs-read-risk.md` — 같은 워크플로의 앞선 보안
  트레이드오프 결정(선례). PR head blob 을 가져오지 않는 원칙의 출처. 이 ADR 과의 경계:
  ADR-002 가 금지하는 것은 **PR head 의 blob** 을 읽는 것이다(신뢰되지 않은 코드가 실행·
  분석 대상이 되는 것). 의장의 read/grep 은 `actions/checkout` 이 놓은 **base-ref**
  워킹트리를 향하므로 그 원칙과 충돌하지 않는다 — base 는 이미 머지된 신뢰되는 코드이고,
  이 리포의 컨벤션(CLAUDE.md/AGENTS.md)을 대조해 패널의 오탐을 기각하는 데 필요하다.
  ADR-002 가 남긴 잔여 위험(fs_read 로 절대경로를 읽어 러너의 자격증명에 도달)은
  `CHAIR_ALLOWED_TOOLS` 로 좁혀지되 사라지지 않으며, `lib.sh::scrub_secrets` 가 마지막
  방어선으로 남는다.

# ADR-004: PR-review fail-closed 게이트의 단일 예외 — 바이너리 자산 삭제 전용 diff

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

**변경 전체가 (a) git 기준 바이너리이고 (b) **삭제**이며 (c) 이미지 확장자이고
(d) 필터에 걸려 리뷰 가능한 텍스트가 0줄로 남은 PR만, 패널을 건너뛰고
`VERDICT: PASS`를 기록한다.**
이것이 fail-closed 정책의 **유일한** 예외다.

핵심은 **판정 근거를 PR 작성자가 통제할 수 없는 값에 두는 것**이다. "필터가 전부
걷어냈다"만을 조건으로 삼으면, 스킵 목록에 경로가 걸리기만 하는 *텍스트* 파일 —
이 리포에 실제로 3개 있는 `package-lock.json`(`src/frontend/`, `scripts/seed-data/`,
`webpage/`) — 만 바꾸는 PR 이 무심사 통과한다. `resolved` URL 과 `integrity` 해시만
갈아끼우는 공급망 PR 이 정확히 그 형태다. 그래서 auto-PASS 자격은 경로 패턴이 아니라
git 이 그 blob 을 바이너리로 판정했는지에 걸려 있다.

전제조건 (셋 다 만족해야 하며, 하나라도 깨지면 기존대로 fail-close):

1. **원본 diff 가 비어 있지 않다** (`[ -s /tmp/pr-diff-raw.txt ]`). 비었다면
   `gh pr diff` 이상 상황이지 "전부 필터됨"이 아니다. 그런데도 PASS 하면 코멘트가
   사실과 다른 근거("전부 패널 필터 대상")를 달고 제외 경로 목록은 빈 채로 게시된다.

2. **필터로 제외된 경로가 실제로 존재한다** (`[ -s /tmp/pr-diff-filtered-paths.txt ]`).
   1번과 함께, 예외의 서술과 실제 상태가 어긋나는 경우를 배제한다.

3. **제외된 것 전부가 git 기준 바이너리이고, 삭제이며, 이미지 자산이다**
   (`[ ! -s /tmp/pr-diff-unsafe-filtered.txt ]`). 세 항목이 각각 다른 구멍을 막는다.

   - **바이너리** — `Binary files ...` / `GIT binary patch` 헝크 유무로 판정한다.
     확장자 추측이 아니라 git 자신의 판정이다. 텍스트라면 패널이 읽을 수 있으니
     읽혀야 한다.
   - **삭제** (`deleted file mode` 헝크) — 이게 rename 우회를 닫는다. `diff --git`
     헤더에서 실용적으로 뽑을 수 있는 건 old 경로(`a/`)뿐인데 rename 은 old 와 new 가
     다르다. `asset.png → payload.zip` 형태의 rename+modify 는 old 경로만 보면
     "png 바이너리"로 자격을 얻으면서 저장소에는 `payload.zip` 을 남긴다 — 즉 이
     예외의 불변식("변경 전체가 자산")이 깨진다. 삭제만 인정하면 그 계열 전체가
     닫힌다: 삭제되는 blob 은 리포에 아무것도 들여오지 않으므로, 컨테이너 안의 내용도
     스크린샷에 찍힌 시크릿도 무심사 통과의 위험이 되지 않는다. 이 예외가 해소하려던
     실제 사례(스크린샷 정리 PR)는 정의상 전부 삭제이므로, 대상은 좁아지지 않는다.
   - **이미지/문서 자산 확장자** (`png|jpg|jpeg|gif|pdf`, `tolower()` 후 매칭) —
     삭제 조건이 이미 대부분을 덮지만,
     "무심사 통과 가능"의 표면을 최소로 유지한다. `pptx` 는 이전 판에서 allow-list 에
     있었는데 제거했다: `zip`/`vsix` 를 컨테이너라는 이유로 제외하면서 같은 OOXML
     ZIP 컨테이너인 pptx 를 허용하는 것은 같은 기준의 자기모순이다. 컨테이너는
     패널을 태운다. `pdf` 는 남겼다 — 그것도 구조화 컨테이너지만, 삭제 조건 아래에서는
     안에 무엇이 들었는지가 무관해진다(리포에 들어오지 않는다). 즉 컨테이너 기준을
     적용하는 축은 "무엇이 들어오는가"이고, pptx 제거는 그 기준의 적용이 아니라
     **표면 최소화**다: 리포에 pptx 삭제 PR 이 실제로 없다.

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
   락파일은 필터에 남아 있고, 전제조건 3번이 그것들만 바뀐 PR 의 auto-PASS 를 막는다
   (텍스트이므로 `unsafe` 로 분류된다). 다만 이것은 필터에서 빼는 것과 **같지 않다**.
   실제 동작은 이렇다: (a) 텍스트가 섞인 PR 에서 npm lockfile 의 `resolved`/`integrity`
   교체는 여전히 어떤 렌즈에도 노출되지 않는다 — 리뷰 커버리지는 복구되지 않는다.
   (b) npm lockfile **만** 바꾸는 PR 은 전제조건 3번에 걸려 fail-close 하므로, 이 ADR 이
   해소하려던 "영구 머지 불가"가 그 종류의 PR 에 대해서는 그대로 남는다(admin merge
   필요). 막은 것은 무심사 통과뿐이고, 그 대가로 얻는 것은 패널의 3000줄 예산을
   lockfile 해시로 잠식하지 않는 것이다. 두 쪽을 다 원하면 npm lockfile 을 필터에서
   빼고 파일당 줄 상한을 도입하는 게 맞는 방향이지만, 이 ADR 의 범위 밖이다.

6. **스킵은 눈에 보이게 한다.** 코멘트에 필터로 제외된 경로 목록을 그대로 싣고
   (백틱은 `&#96;`로 이스케이프 — 파일명으로 마크다운을 주입하지 못하게),
   `panel_responded=skipped (...)`, `chair_used=no chair — panel skipped`를 설정해
   의장이 실행된 것처럼 보이지 않게 한다. 전제조건이 깨져 fail-close 할 때는
   어느 **전제조건 번호**가 깨졌는지, 그리고 어느 경로가 자격을 박탈했는지
   `::error::`로 각각 남긴다.

7. **필터 목록과 예외 범위는 커플링되어 있다.** awk 스킵 목록에 확장자나 경로를 추가하면
   auto-PASS 후보가 함께 넓어진다(전제조건 3번이 걸러주지만, 새 바이너리 확장자를
   allow-list 에 넣는 경우는 걸러지지 않는다). 목록을 건드릴 때 이 ADR을 같이 갱신한다.
   스킵 목록 awk 와 allow-list awk 양쪽에, 그리고 파일 상단 주석에 그 요구를 남겼다.

8. **awk 프로그램 안에 아포스트로피를 쓰지 않는다.** 세 awk 블록 모두 셸에서
   단일 인용으로 감싸여 있어서, 주석 안의 `panel's` 하나가 인용을 닫고 스텝을
   셸 구문 오류로 죽인다. `pull_request_target` 은 base-ref 의 워크플로 파일을
   실행하므로 이 종류의 실수는 브랜치에서 CI 로 드러나지 않는다 — 머지된 뒤에
   드러난다. 이 PR 을 오프라인 하네스로 검증하다가 실제로 하나 잡았다.

9. **Terraform state/plan 산출물은 스킵도 리뷰도 아니라 즉시 실패다.** 처음에는
   `*.tfstate`/`*.tfplan` 를 스킵 목록에 넣었는데, 그게 최악의 조합이었다. 두 가지
   이유로 그렇다.
   - **혼합 PR 에서 조용히 사라진다.** unsafe 분류 검사는 `[ ! -s ...truncated ]`
     블록 안에서만 돌기 때문에, `.tf` 변경과 state 가 함께 커밋된 PR 은 그 검사에
     아예 도달하지 않는다. state 만 필터에 먹히고 패널은 나머지를 리뷰하며,
     `::error::` 도 없다. 스킵 이전에는 최소한 렌즈에 노출되었으니 순수한 회귀다.
   - **state-only 정리 PR 이 새 영구 머지 불가가 된다.** state 는 git 기준 텍스트라
     unsafe 로 분류되어 fail-close 한다 — 하필 위생상 가장 장려해야 할 PR 종류에,
     이 ADR 이 없애려던 실패 모드가 재생성된다.

   프롬프트에 싣는 것도 답이 아니다: Aurora/DocumentDB master password 가 평문으로
   들어 있고, 그게 4모델×4렌즈로 외부 provider 에 나간다. 그래서 세 번째 선택지를
   쓴다 — raw diff 에서 state/plan 경로가 검출되면 diff 구성과 무관하게 `::error::` +
   `exit 1`. 패턴은 `*.tfstate`, `*.tfstate.<n>`, `*.tfstate.backup`, `*.tfplan`,
   확장자 없는 `tfplan`/`plan.out`, `terraform.tfstate.d/` 를 덮는다. 유일한 해소
   경로는 브랜치에서 그 커밋을 되돌리는 것이며(그리고 노출된 자격증명 회전),
   에러 메시지가 그 절차를 지시한다.

## Consequences

**얻는 것**

- 게이트를 우회(admin merge)해야만 머지되는 PR 종류가 사라진다. 통제 우회를 정상 절차로
  만들지 않는다.
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
- 필터 목록이나 확장자 allow-list 가 넓어질 때 auto-PASS 범위가 조용히 넓어질 수 있다 —
  위 7번이 그에 대한 방어이며, 사람의 규율에 의존한다.
- npm lockfile-only PR 은 여전히 fail-close 로 남는다(5번). 이 ADR 이 고치는 것은
  바이너리 자산 삭제 PR 한 종류뿐이다.
- state/plan 결정론적 deny(아래 9번)로 인해, 그 파일이 들어 있는 PR 은 패널·의장·예외
  판정 이전에 잡이 죽는다. 브랜치에서 커밋을 되돌리는 것 외에 통과 경로가 없다 —
  admin merge 로도 게이트 실패는 남는다. 이건 의도된 것이다.

## References

- `.github/workflows/pr-review.yml` — "Get PR diff"(필터 + 바이너리 분류),
  "Build lens prompts"(`head -3000` 절단 — 판정 대상 파일이 여기서 생성된다),
  "Run panel + synthesize"(전제조건 검사 + auto-PASS)
- `scripts/pr-review/run-panel.sh` — 빈 diff fail-close 지점(`-s` 기준의 근거)
- `docs/decisions/ADR-002-pr-review-kiro-fs-read-risk.md` — 같은 워크플로의 앞선 보안
  트레이드오프 결정(선례). PR head blob 을 가져오지 않는 원칙의 출처.

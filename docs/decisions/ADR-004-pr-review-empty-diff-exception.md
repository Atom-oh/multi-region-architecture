# ADR-004: PR-review fail-closed 게이트의 단일 예외 — 리뷰 가능한 텍스트가 0줄인 diff

## Status

Accepted (2026-07-28).

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

**필터 후 리뷰 가능한 텍스트가 0줄이면 패널을 건너뛰고 `VERDICT: PASS`를 기록한다.**
이것이 fail-closed 정책의 **유일한** 예외다.

경계 조건:

1. **판정 근거는 실제로 패널에 전달할 파일이다.** `total_lines`(GITHUB_ENV로 넘어온 값)를
   믿지 않고 `/tmp/pr-diff-truncated.txt`를 다시 센다. 스텝이 재배치되어 변수가
   사라지면 `${total_lines:-0}`은 조용히 0으로 접혀 *모든* PR을 auto-PASS 시킨다 —
   fail-open으로의 단일 실패점이므로 넘겨받은 값에 의존하지 않는다.

2. **`.terraform.lock.hcl`은 필터에서 제외하지 않는다.** provider 버전과 무결성 해시를
   고정하는 파일이고, IaC 리포에서 리뷰할 가치가 있는 사실상 유일한 공급망 표면이며,
   무엇보다 **읽을 수 있는 텍스트**다. 다른 락파일(npm/yarn/pnpm)과 달리 스킵 대상이
   아니다. 이 결정 이전에는 필터에 있었고, 그 상태로 예외를 도입하면
   `.terraform.lock.hcl`만 바꾸는 PR이 무심사 통과했을 것이다.

3. **스킵은 눈에 보이게 한다.** 코멘트에 필터로 제외된 경로 목록을 그대로 싣고,
   `panel_responded=skipped (...)`, `chair_used=no chair — panel skipped`를 설정해
   의장이 실행된 것처럼 보이지 않게 한다. 사람이 스킵의 타당성을 워크플로 말만 믿지 않고
   확인할 수 있어야 한다.

4. **필터 목록과 예외 범위는 커플링되어 있다.** awk 스킵 목록에 확장자나 경로를 추가하면
   auto-PASS 범위가 함께 넓어진다. 목록을 건드릴 때 이 ADR을 같이 갱신한다.

## Consequences

**얻는 것**

- 게이트를 우회(admin merge)해야만 머지되는 PR 종류가 사라진다. 통제 우회를 정상 절차로
  만들지 않는다.
- `.terraform.lock.hcl`이 리뷰 대상으로 승격된다 — 예외를 도입하려고 살펴본 덕에 발견한,
  이전부터 있던 공백이다.

**받아들이는 리스크**

- 바이너리 전용 PR에 대한 심사가 없다. 단, 패널은 원래 바이너리를 읽지 못했으므로 이
  변경으로 커버리지가 *줄어드는* 것은 아니다. 이미지에 시크릿이나 악성 페이로드를 심는
  경로는 이 게이트가 전에도 잡지 못했다. 방어를 원한다면 이 예외를 되돌리는 것이 아니라
  auto-PASS 경로에 gitleaks류 스캐너를 추가하는 것이 맞는 대응이다.
- 필터 목록이 넓어질 때 auto-PASS 범위가 조용히 넓어질 수 있다 — 위 4번이 그에 대한
  유일한 방어책이며, 사람의 규율에 의존한다.

## References

- `.github/workflows/pr-review.yml` — "Get PR diff", "Run panel + synthesize" 스텝
- `scripts/pr-review/run-panel.sh` — 빈 diff fail-close 지점
- ADR-002 — 같은 워크플로의 앞선 보안 트레이드오프 결정(선례)

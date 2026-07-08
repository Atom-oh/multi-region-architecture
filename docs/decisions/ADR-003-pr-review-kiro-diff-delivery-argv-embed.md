# ADR-003: PR-Review Kiro Diff Delivery — `fs_read` → capped argv embed

## Status

Accepted (2026-07-08) — supersedes ADR-002's acceptance of the `fs_read` residual
exfiltration risk. ADR-002's other fixes in the same pass (TOCTOU symlink guards on
`ensure_slots()`/`$KIRO_CWD`, the hardened exact-last-line `VERDICT:` gate,
`persist-credentials: false`) are unaffected and remain in effect.

## Context

ADR-002 accepted `--trust-tools=fs_read` for Kiro's diff delivery as a residual risk,
reasoning: "the general 'absolute-path `fs_read` can read anything the runner's OS user can
read' capability has no full mitigation without dropping `fs_read` entirely (**which would
break Kiro's diff delivery** — Kiro's `chat` ignores stdin)."

That premise was wrong: dropping the `fs_read` tool grant does not require dropping diff
delivery — it only requires delivering the diff through a channel other than a
Kiro-readable file path. Kiro's `chat` ignores stdin but does read its prompt argument
(argv), and the diff can be embedded directly into that argument instead of referenced by
path. An AI review of the identical lens×model matrix design ported to a sibling repo
(`claude-code-usage-dashboard` PR #4) identified this and escalated the residual risk to
CRITICAL for the reasons ADR-002 itself already listed as unmitigated: `pull_request_target`
with privileged CI credentials in scope, and a successful exfiltration surfaces in the
**chair-synthesized PR comment itself**, not just via the external Kiro service leg.

## Decision

- `scripts/pr-review/run-panel.sh`: Kiro cells receive `--trust-tools=` (empty — grants no
  tools at all) instead of `--trust-tools=fs_read`. Verified live against the real
  `kiro-cli chat --help`: `"trust no tools: '--trust-tools='"` is the documented syntax,
  confirmed further by direct reproduction (an injected "read /etc/passwd via fs_read"
  instruction is refused, not executed, under `--trust-tools=`).
- The diff is capped (`KIRO_DIFF_CAP`, default 100000B — safely under the kernel's
  `MAX_ARG_STRLEN` ~128KiB per-argument limit) and embedded directly into the `chat`
  argument, replacing the file-path reference ADR-002 relied on.
- **New coverage-signal gap closed in the same pass**: a diff exceeding `KIRO_DIFF_CAP`
  previously left Kiro cells reviewing only a truncated prefix with no signal — silently
  degrading coverage for the diff's tail. `run-panel.sh` now emits `::warning::` and a
  `$WORK/kiro-diff-truncated.flag`; `synthesize.sh` surfaces it as an advisory banner
  (does not force `VERDICT: FAIL` — codex still reviews the full diff via stdin).
- **Coverage-severe gate corrected from model-count to vendor-count**: the prior gate
  compared `degraded_count >= TOTAL_MODELS - 1`, which never tripped when codex alone died
  (1 of 4 models) even though the surviving panel was then 100% Kiro — contradicting the
  gate's own "≤1 vendor" framing. Now checks the two actual vendor families directly:
  severe iff codex is dead OR every Kiro model is dead.
- Isolated `$HOME`/cwd for Kiro (`$KIRO_CWD`, TOCTOU-guarded per ADR-002) is retained as
  defense-in-depth (cache/session-state hygiene across non-ephemeral-runner reuse) but is
  no longer load-bearing for the exfiltration threat model — there is no tool grant left to
  exploit via `~`-relative or absolute-path tricks.
- `persist-credentials: false` (ADR-002 decision 1) remains in effect — it's an orthogonal
  defense-in-depth against any *other* future absolute-path read vector, not specific to
  `fs_read`.
- Scope: **CI pr-review only**, same as ADR-002. co-agent's own Kiro fan-out is unaffected.

## Consequences

- Closes the `fs_read` exfiltration path structurally instead of accepting it as residual
  risk — ADR-002's "no full mitigation without breaking diff delivery" premise no longer
  holds, since diff delivery and tool grants turned out to be independent.
- Trades one bounded, signaled limitation (diffs over `KIRO_DIFF_CAP` get prefix-only Kiro
  coverage, now visible via the truncation banner) for one closed, unbounded one
  (arbitrary-path read).
- Any future change to `kiro-cli`'s documented `--trust-tools=` semantics must re-verify
  this ADR's fail-closed assumption (no automated regression test currently probes for it
  beyond the coverage floor, which cannot distinguish "no tools granted" from "tools
  granted but the diff happened not to trigger their use").

## References

- `scripts/pr-review/run-panel.sh`, `lib.sh`, `synthesize.sh`
- ADR-002 (the `fs_read` decision this ADR supersedes; TOCTOU/VERDICT-gate/
  persist-credentials fixes from the same ADR remain in effect)
- `claude-code-usage-dashboard` PR #4 (source of the finding)
- oh-my-cloud-skills ADR-013 (the original design's own version of this decision — this
  repo's ADR-003 documents the same decision independently for this repo's history)

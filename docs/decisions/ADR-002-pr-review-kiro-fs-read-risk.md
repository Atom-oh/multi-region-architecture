# ADR-002: PR-Review Kiro `fs_read` — Residual Exfiltration Risk (historical — eliminated, see Status)

## Status

Accepted (2026-07-07). **Decision #2 (accept the residual risk) is superseded** —
`fs_read` has since been dropped entirely in favor of embedding the diff directly as
capped argv text (`--trust-tools=`, no tool grant). Decision #2's premise — "dropping
`fs_read` would break Kiro's diff delivery, since `chat` ignores stdin" — turned out to
be a false dichotomy: argv embedding needs neither stdin nor `fs_read`, and is now
verified working across the fleet (`oh-my-cloud-skills`, `cc-on-bedrock`,
`AWS-Demo-Platform`, `claude-code-usage-dashboard`, `ttobak`, `security-ops`). This also
closes a second, independent problem Decision #2 didn't cover: a Kiro cell that never
calls `fs_read` (or has the call fail silently) can still return a plausible non-empty
"no findings" response, which the coverage-floor gate can't distinguish from a real
review (cc-on-bedrock PR#107 review, MAJOR-1). Decisions #1, #3, #4 below remain valid
and unaffected — they don't depend on `fs_read` being in use.

## Context

The PR-review CI panel (lens×model matrix, `scripts/pr-review/*`) moved Kiro's diff
delivery from an invalid `--trust-tools=read,grep` to the real read-only tool name
`--trust-tools=fs_read`. `fs_read` is read-capable for absolute paths, and it runs against
an **untrusted PR diff** injected as the review prompt — a `pull_request_target` job with
self-hosted-runner secrets in scope. A diff-borne prompt injection could instruct Kiro to
`fs_read` a fixed credential path (e.g. `.git/config`'s persisted `GITHUB_TOKEN`, or an EKS
Pod Identity token file) and have the value appear in its response, which Claude then
synthesizes — and Kiro itself is an **external service**, so the read value would leave the
region/account before any scrub runs.

## Mitigations Already In Place

- Isolated `$HOME`/cwd for the Kiro subprocess (`KIRO_CWD`) — closes the `~`-relative
  path vector (real credentials aren't under the fake `$HOME`).
- `env -i` allowlist — only `KIRO_API_KEY` and the minimum needed vars reach Kiro;
  `AWS_*`/`GH_TOKEN` are never passed via environment.
- `scrub_secrets()` — a last-line-of-defense regex pass over every cell's output before
  it reaches the chair or a public PR comment.

## Residual Risk (historical — superseded, see Status)

This section describes the risk as it stood when `fs_read` was still granted to Kiro
cells. It no longer reflects the current implementation — see Status/Decision #2:
`fs_read` is not granted at all anymore, so the absolute-path read vector this section
describes is *conditionally* eliminated (not unconditionally — see Decision #2's
`KIRO_SEMANTIC_OK` caveat; an earlier revision of this line overstated the guarantee as
unconditional, multi-region-architecture PR#28 review). Kept for historical record.

None of the mitigations above stopped an **absolute-path** `fs_read` from succeeding —
`fs_read` is read-capable by design and the isolation only affected env vars and
`~`-relative lookups. The concrete residual path: `actions/checkout`'s default
`persist-credentials: true` writes `GITHUB_TOKEN` into `.git/config`; a diff-borne
injection reading that absolute path would have `scrub_secrets()` catch a well-formed
GitHub token pattern, but a differently-shaped or partial secret could still slip through
as the *first* line of defense, not a guarantee.

## Decision

1. **`persist-credentials: false`** on this workflow's `actions/checkout@v4` step — removes
   the one concrete, known-shape credential this design would otherwise leave on disk.
   This is a direct fix, not just documentation.
2. ~~Accept as residual risk, not blocking~~ — **superseded, see Status**. `fs_read` is no
   longer granted to Kiro cells; the diff is embedded directly in the `chat` argv instead
   (capped at `KIRO_DIFF_CAP`, matching the `PANEL_CELL_CAP` convention used elsewhere).
   This eliminates the absolute-path read vector **conditional on `--trust-tools=`'s
   "no tools" semantic actually holding** — not unconditionally, as an earlier version of
   this section claimed (multi-region-architecture PR#28 review L5-MAJOR). `run-panel.sh`
   re-verifies this at the start of every run via `KIRO_SEMANTIC_OK`: a help-text phrase
   grep, plus a behavioral canary that plants a marker file and asks **every model in
   `KIRO_MODELS`** (not just one representative — `--trust-tools=` being CLI-layer and
   therefore model-independent is exactly the assumption the canary exists because we
   don't trust; verifying only one model would be self-defeating, PR#28 review
   L3-MAJOR-2) to read it back with no tool grant. The canary is **leak-absence-only**,
   not a confirmed-refusal check: a non-empty response that doesn't contain the marker
   counts as a pass, whether or not the model's wording is an explicit refusal (PR#28
   review L3-MAJOR-1/L5-MAJOR-1) — this is enough to satisfy the canary's actual purpose
   (detect an active leak), but is a weaker property than "confirmed the model refused."
   A canary call that itself fails or times out (network/auth/etc.) does **not** count as
   a pass and skips all Kiro cells that run, same as a detected leak. All Kiro cells are
   skipped if any model's check fails — but the elimination is only as durable as that
   guard, pinned to kiro-cli 2.11.1's documented and observed behavior. If a future
   kiro-cli version changes the semantic in a way the canary doesn't catch (e.g. the model
   simply doesn't attempt to use the now-available tool during this one probe), this
   reverts to an accepted-risk situation, not an eliminated one.
   `scrub_secrets()` remains in place as defense-in-depth for other leak paths (e.g. an
   errored cell's raw stderr), just not as the last line of defense for this one anymore.
3. **Also fixed in this pass**: `lib.sh`'s `ensure_slots()` and `run-panel.sh`'s
   `$KIRO_CWD` setup now refuse to operate if their fixed, non-ephemeral-runner path
   (`$WORK/slot`, `$WORK/kiro-cwd`) is a symlink, closing a separate TOCTOU concern where
   another job could preempt the fixed path before this job's `rm -rf`. The `Check for
   blocking issues` gate step now requires `VERDICT: PASS|FAIL` to be the file's exact
   last line (plus exactly one `VERDICT:` line for PASS), instead of matching anywhere in
   the file.
4. Scope: **CI pr-review only**. This does not change co-agent's own Kiro fan-out, which
   uses the same tool but is interactive/on-demand rather than a `pull_request_target` gate
   over untrusted PR content.

## Consequences

- The one concrete, addressable leak (persisted `GITHUB_TOKEN`) was closed by Decision #1
  regardless of the `fs_read` question, and remains closed.
- The general absolute-path read capability is conditionally eliminated: Kiro cells get no
  tool grant at all, so there's no read path left to abuse *as long as* `--trust-tools=`'s
  empty-value semantic holds — re-verified every run via `KIRO_SEMANTIC_OK` (see Decision
  #2). Two independent caps can each trigger truncation: `KIRO_DIFF_CAP` (default 100000B,
  same capping convention as `PANEL_CELL_CAP`, default 20000B) bounds the diff slice
  itself (`kiro-diffcap-fired.flag`), and `KIRO_ARGV_CAP` (default 125000B, headroom under
  the 131072B `MAX_ARG_STRLEN` kernel limit) bounds the final assembled `LENS_PROMPT` +
  diff instruction (`kiro-argvcap-fired.flag`) — an oversized lens prompt can trigger the
  latter even when the diff itself is well under `KIRO_DIFF_CAP`. If a lens prompt is so
  large that even the maximally-trimmed instruction still exceeds `KIRO_ARGV_CAP`, that
  lens's Kiro cells are skipped entirely rather than sent an oversized argv
  (`kiro-lens-skipped.flag`). `synthesize.sh`'s banner distinguishes all three cases so the
  cause isn't misattributed to `KIRO_DIFF_CAP` when only the argv cap fired
  (multi-region-architecture PR#28 review L5-MAJOR-1, fixed after an earlier revision of
  this PR shared one flag across all three causes).
- **Truncation escalates to a forced `VERDICT: FAIL`, overriding the chair's own judgment,
  when `codex` is *also* degraded that run** (binary absent, timeout, or auth failure) —
  in that combination, nobody reviewed the diff past the truncation point, which is
  equivalent to zero surviving vendors for that segment. This is the same fail-closed
  treatment `coverage-severe.flag` already gives an all-but-one-vendor-degraded run, just
  triggered by a different combination of conditions (multi-region-architecture PR#28
  review L5-MAJOR-2 — this escalation existed in the code before this ADR line was added
  to describe it).

## References

- `scripts/pr-review/run-panel.sh` (Kiro cell: `kiro_env`, `KIRO_CWD_BASE`/`CELL_CWD`,
  `--trust-tools=`, `KIRO_DIFF_CAP`/`KIRO_DIFF_TEXT`, `KIRO_SEMANTIC_OK` canary gate,
  `KIRO_ARGV_CAP`/`KIRO_LENS_OVERSIZED`, flag files: `kiro-diffcap-fired.flag`,
  `kiro-argvcap-fired.flag`, `kiro-lens-skipped.flag`)
- `scripts/pr-review/lib.sh` (`scrub_secrets`, `ensure_slots`)
- `.github/workflows/pr-review.yml` (`persist-credentials: false`, hardened VERDICT gate)
- `oh-my-cloud-skills` — original source of the argv-embed fix (round 19 review,
  CRITICAL — cwd/HOME isolation alone did not stop an absolute-path `fs_read` in a live
  reproduction). Correction: the previous version of this ADR cited "cc-on-bedrock
  ADR-013" and "ttobak ADR-019" documenting the same accepted-risk trade-off — neither
  ADR exists in those repos; that reference was unverified and is removed. Only
  `aws-fsi-demo`'s `ADR-012-pr-review-kiro-fs-read-risk.md` is a real sibling document
  (same trade-off, same correction pending there).

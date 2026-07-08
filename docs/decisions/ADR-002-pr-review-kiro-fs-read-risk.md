# ADR-002: PR-Review Kiro `fs_read` — Residual Exfiltration Risk (Accepted, Mitigated)

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

## Residual Risk (Accepted)

None of the above stops an **absolute-path** `fs_read` from succeeding — `fs_read` is
read-capable by design and the isolation only affects env vars and `~`-relative lookups.
The concrete residual path: `actions/checkout`'s default `persist-credentials: true` writes
`GITHUB_TOKEN` into `.git/config`; a diff-borne injection reading that absolute path would
have `scrub_secrets()` catch a well-formed GitHub token pattern, but a differently-shaped or
partial secret could still slip through as the *first* line of defense, not a guarantee.

## Decision

1. **`persist-credentials: false`** on this workflow's `actions/checkout@v4` step — removes
   the one concrete, known-shape credential this design would otherwise leave on disk.
   This is a direct fix, not just documentation.
2. ~~Accept as residual risk, not blocking~~ — **superseded, see Status**. `fs_read` is no
   longer granted to Kiro cells; the diff is embedded directly in the `chat` argv instead
   (capped at `KIRO_DIFF_CAP`, matching the `PANEL_CELL_CAP` convention used elsewhere).
   This eliminates the absolute-path read vector outright rather than accepting it.
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
- The general absolute-path read capability is no longer an accepted risk — it's
  eliminated: Kiro cells get no tool grant at all, so there's no read path left to abuse.
  `KIRO_DIFF_CAP`-driven truncation (100KB, matching `PANEL_CELL_CAP`) is now the
  accepted trade-off instead, made visible via a `kiro-diff-truncated.flag` banner in
  the synthesized review rather than silently dropping coverage.

## References

- `scripts/pr-review/run-panel.sh` (Kiro cell: `kiro_env`, `KIRO_CWD`, `--trust-tools=`,
  `KIRO_DIFF_CAP`/`KIRO_DIFF_TEXT`)
- `scripts/pr-review/lib.sh` (`scrub_secrets`, `ensure_slots`)
- `.github/workflows/pr-review.yml` (`persist-credentials: false`, hardened VERDICT gate)
- `oh-my-cloud-skills` — original source of the argv-embed fix (round 19 review,
  CRITICAL — cwd/HOME isolation alone did not stop an absolute-path `fs_read` in a live
  reproduction). Correction: the previous version of this ADR cited "cc-on-bedrock
  ADR-013" and "ttobak ADR-019" documenting the same accepted-risk trade-off — neither
  ADR exists in those repos; that reference was unverified and is removed. Only
  `aws-fsi-demo`'s `ADR-012-pr-review-kiro-fs-read-risk.md` is a real sibling document
  (same trade-off, same correction pending there).

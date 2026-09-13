# Specialist review protocol

Inactive MRA adapter stage. Common executors and the MRA collector adapter/policy
are installed; the operational workflow still uses its legacy panel/chair.
Workflow activation and E2E tests follow separately.

| Tag | Requested model | Scope |
| --- | --- | --- |
| codex | `global.openai.gpt-6-astra` | Implementation/tests |
| kiro-fable | `claude-opus-5` | AWS/IAM/network |
| kiro-sol | `gpt-5.6-sol` | Deployment/contracts/recovery |
| claude-self | `global.anthropic.claude-fable-5-1` | Auth/data/API/ADR |

`kiro-fable` means Opus. `ROLES` governs specialists; legacy files govern legacy
execution. Kiro/Bedrock IDs differ. English is requested, not validated; configured
IDs do not attest model weights.

## Installed common libraries

`run-specialists.sh` coordinates one role per applicable tag; `run_role.py` sends
issued requests, validates process/transport outcomes and records scrubbed results.
Codex validates JSONL events and its private final-output file. Kiro uses an empty
catalog and fixed no-tools canary in an isolated environment. `synthesize_roles.py`
selects deterministic output or bounded chair adjudication.

`prepare_roles.py` validates a pinned BASE checkout. Its generic branch can load a
committed, byte-matched `prepare_context_roles.py`; absence preserves root context.
No such context helper is installed here: MRA uses the project adapter below,
which takes precedence over generic preparation. See [ADR-005](../../docs/decisions/ADR-005-specialist-review-protocol.md).

## MRA collector adapter (not selected by CI)

`role-project.json` selects `prepare_project_roles.py`, canonical BASE `CLAUDE.md`
plus `mra-review-context.md`, and the mandatory chair policy: 600-second attempts,
8/12 turns, Read/Grep/Glob allowed, and Bash/Write/Edit/NotebookEdit/WebFetch/
WebSearch/Task always denied. Read tools have no filesystem path confinement.

From the pinned BASE checkout, collect all files API pages between two immutable
HEAD/base snapshots, then create the approved bundle before deleting raw API files:

```bash
python3 scripts/pr-review/prepare_project_roles.py \
  --files "$FILES_JSON" --before "$BEFORE_JSON" --after "$AFTER_JSON" \
  --head "$HEAD_SHA" --base "$BASE_SHA" --merge-base "$MERGE_BASE_SHA" --output "$BUNDLE"
python3 scripts/pr-review/prepare_roles.py --prepared-diff "$BUNDLE/panel.diff" --work "$WORK"
```

Snapshot JSON contains `head_sha`/`base_sha`. The bundle retains `panel.diff`,
`collection.json` and patch-free `collection-meta.json`. State-deletion bodies are
removed before persistence. The caller must delete original raw API responses
before providers or the chair run. Publish safe metadata, never raw request bodies.

The hook receives `prepare(head, base, merge_base, work, supplied_diff)` and returns
`diff`/`context` bytes, reviewable `paths`, `provenance` and `input_failures`.
Missing/mismatched bundles block; raw Git reconstruction is not a fallback.
It replays the BASE collector and checks snapshots, source digest and every files
API path/status against a NUL-delimited Git manifest. Safe blob IDs/counts survive.
The plan/request binds scope and source/context/diff hashes; metadata is data.

ADR-004 state/plan additions, modifications and renames block. Eligible deletion
bodies stay withheld. API-omitted oversized text deletions use explicit `path_only`
metadata and actual tree mode without fetching old bodies. Mixed input retains all
reviewable text. The eligible deletion-only result is reserved for the trusted
workflow shortcut; ordinary empty input never receives role PASS. MRA installs no
generic `role-input-scope.json` or exclusions-only opt-in. Workflow/E2E integration
must preserve this custody and provide safe deletion-only artifacts.

## API and input

`python3 scripts/pr-review/role_review.py COMMAND --help` lists flags.

| Command | Contract |
| --- | --- |
| prepare | Diff/context, HEAD/base, work; optional paths/provenance → `role-plan.json`, `roles/TAG.txt/.diff`. |
| issue | Work/tag → nonce, exact `requests/TAG.prompt/.input`, `slot/TAG-request.json`. Call before each attempt. |
| record | Tag, output/stderr, exit code, issued nonce → validated, scrubbed `slot/TAG-result.json`. |
| aggregate | Validate results/receipts → `role-summary.json`, `responded.txt`, `chair-mode.txt`, applicable report/flag. |

The executor sends issued bytes; hashes bind inputs, not transport. Keep tool data
out of diagnostics.

`--paths FILE`: UTF-8 JSON array of unique repository-relative paths matching the patch,
e.g. `["src/api.ts"]`. Renames use destinations; the collector checks both sides.
Omit only for authoritative, unambiguous patch paths.

`--provenance FILE`: JSON object. Required `head_sha`/`base_sha` equal the lowercase
40-character CLI revisions; `diff_sha256` hashes exact raw diff bytes. Example:

```json
{"head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","base_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","diff_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}
```

Optional `input_failures` contains codes matching `[a-z][a-z0-9_:.-]{0,63}`; any code
blocks. Invalid provenance is discarded and blocks; stored values are scrubbed.
Optional `path_only: list[str]` identifies collector-approved metadata-only
deletions. Verify eligibility before withholding bodies.

## Coverage and lifecycle

Codex/Claude are required for reviewable source; trusted routing may deactivate
irrelevant Kiro roles. App Router React is conservative. Failed output is never
N/A. Parsing misses whole omissions/some cut prefixes: verify Git scope/hashes.

BASE-approved exclusions-only scope may yield NOT_APPLICABLE/PASS without models.
Require empty diff/paths, `scope_exception: configured_exclusions_only`, lowercase
64-character `input_policy_sha256`, and identical nonempty unique safe
`scope_paths`/`excluded_paths`. Caller MUST verify trusted BASE policy and complete
Git scope; the library cannot establish repository membership. Reports disclose
exclusions/hash. Accidental empty input never qualifies.

Start fresh work before collection. `prepare` clears owned results/receipts, claims,
duplicate/terminal flags and histories; upstream flags remain. Issue/record exclude
each other; interrupted operations require fresh work. Duplicate records retain
the first result and block. Finish writers before aggregation. Reissue of failed results archives
at most 32 prior results in `slot/TAG-attempts.json`; model-selection/fallback/quota/preflight
failures block until new preparation. Summaries retain history. All `*.flag` files
block except root `coverage-severe.flag`. `failure_codes` is canonical; `failures` aliases it.

Exit 2 means blocked. Aggregate exit 0: `deterministic` permits the report when no
blocking candidate/uncertainty exists (Minor/Info remain); `review` needs a chair.
Blocked input yields deterministic FAIL; the chair cannot waive coverage failures.

Publish scrubbed reports/receipts/metadata only; never raw `roles/*.diff` or
`requests/*.input/.prompt`.

## Limits and checks

Limits: 95,000 diff bytes (UTF-8), 3,000 lines, 24,000 context bytes, <128 KiB
request; projects may lower them. Oversize blocks. No chunk coordinator or
combining partial PASS results; preserve custody/budgets.

Run `python3 -m unittest discover -s scripts/pr-review -p 'test_*role*.py'`.
Offline CI: `.github/workflows/pr-review-roles-tests.yml`. Activation also needs
executor/adapter, limit and exact-HEAD publication tests; offline success proves
no live provider execution.

Sol replaces this repository's legacy Terra slot at activation; application
inference models remain unchanged.

MRA retains ADR-004 collector/state-deletion custody and its deletion-only shortcut.
These stages do not configure generic exclusions-only scope for MRA (ADR-005).

Exclusions-only review requires both `--allow-exclusions-only --policy FILE`.
The trusted BASE collector supplies a schema-1 policy; its exact bytes must match
`input_policy_sha256`. The private `exclusions-policy.json` anchor is rechecked
during aggregation. Missing or mismatched opt-in blocks. The collector, not this
offline library, must establish complete Git scope and approved exclusions.

A valid result cannot be reissued to discard findings or uncertainty. Start a new
preparation for a new review; failed attempts retain their diagnostic history.

The model table targets CI's Bedrock Runtime provider. Local Mantle uses
`openai.gpt-6-astra` for Astra; provider-specific identifiers are not interchangeable.

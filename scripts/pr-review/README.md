# Specialist review protocol

The workflow selects `ROLE_REVIEW=1` through the MRA adapter and bounded chair
policy. Legacy branches remain for regression fixtures, not an operational toggle.
Current-HEAD review and required CI precede merge; offline tests are not live inference.

| Tag | Requested model | Scope |
| --- | --- | --- |
| codex | `global.openai.gpt-6-astra` | Implementation/tests |
| kiro-fable | `claude-opus-5` | AWS/IAM/network |
| kiro-sol | `gpt-5.6-sol` | Deployment/contracts/recovery |
| claude-self | `global.anthropic.claude-fable-5-1` | Auth/data/API/ADR |

`kiro-fable` means Opus. `ROLES` governs specialists; legacy files govern legacy
execution. Kiro/Bedrock IDs differ. English is requested, not validated; configured
IDs do not attest model weights.

## Slot mapping

| Protocol tag | Legacy `run-panel.sh` slot | Model selection |
| --- | --- | --- |
| `kiro-fable` | `kiro-opus` | `claude-opus-5` remains selected |
| `kiro-sol` | `kiro-gpt` | `gpt-5.6-sol` selected |

These are different label namespaces. The protocol tag does not rename the
legacy slot; the workflow selects the role-based execution path.

## Installed common libraries

`run-specialists.sh` coordinates one role per applicable tag; `run_role.py` sends
issued requests, validates process/transport outcomes and records scrubbed results.
Codex validates JSONL events and its private final-output file. Kiro uses an empty
catalog and a random canary with expected `NO_TOOLS` response. `synthesize_roles.py`
selects deterministic output or bounded chair adjudication. Claude specialists
set `--tools ""`, `--disallowedTools "*"`, `--max-turns 1` and strict MCP configuration;
fake CLIs exercise denial without claiming live inference.

`prepare_roles.py` validates a pinned BASE checkout. Its generic branch can load a
committed, byte-matched `prepare_context_roles.py`; absence preserves root context.
No such context helper is installed here: MRA uses the project adapter below,
which takes precedence over generic preparation. See [ADR-005](../../docs/decisions/ADR-005-specialist-review-protocol.md).

## MRA collector adapter

`role-project.json` must match its committed BASE bytes before adapter selection.
The chair verifies that checkout and the prepared policy hash before using its limits.
The profile selects `prepare_project_roles.py`, canonical BASE `CLAUDE.md`
plus `mra-review-context.md`, and the mandatory chair policy: 600-second attempts,
8/12 turns, Read/Grep/Glob allowed, and Bash/Write/Edit/NotebookEdit/WebFetch/
WebSearch/Task always denied. Read tools have no filesystem path confinement.

The caller must already have the BASE, HEAD and merge-base commit objects locally.
A shallow BASE checkout plus fetching those exact revisions is sufficient; complete
Git history is not required. Fetching objects is not permission to reconstruct
withheld state/plan bodies. The activation workflow supplies this prerequisite.

Set `HEAD_SHA`, `BASE_SHA` and `GH_REPO`. From the pinned BASE checkout, collect
all files API pages between two immutable
HEAD/base snapshots, then create the approved bundle before deleting raw API files:

```bash
python3 scripts/pr-review/prepare_project_roles.py \
  --files "$FILES_JSON" --before "$BEFORE_JSON" --after "$AFTER_JSON" \
  --head "$HEAD_SHA" --base "$BASE_SHA" --merge-base "$MERGE_BASE_SHA" --output "$BUNDLE"
python3 scripts/pr-review/prepare_roles.py --prepared-diff "$BUNDLE/panel.diff" --work "$WORK"
```

The shared preparer obtains merge-base identity from GitHub's compare API and
requires the bundle to match; shallow checkout history is not used to recompute it.
After collection, the installed entrypoints are:

- `run-specialists.sh BUNDLE/panel.diff UNUSED WORK`
- `run_role.py --work WORK --tag TAG`
- `synthesize_roles.py --work WORK --output REPORT`

Snapshot JSON contains `head_sha`/`base_sha`. The bundle retains `panel.diff`,
`collection.json` and patch-free `collection-meta.json`. State-deletion bodies are
removed before persistence. The caller must delete original raw API responses
before providers or the chair run. Publish safe metadata, never raw request bodies.

The adapter's ordered `SOURCES` tuple defines context assembly. The profile declares
the same sources; the common preparer rejects a mismatch, and MRA unit tests bind
the exact order and actual chair options to the committed profile. Candidate
`CLAUDE.md`/ADR-summary blobs are read only for availability and size validation,
then discarded. Missing or moved context sources block until their migration is
reviewed; this is an input-readiness failure, not proof of forged provenance.

The hook receives `prepare(head, base, merge_base, work, supplied_diff)` and returns
`diff`/`context` bytes, reviewable `paths`, `provenance` and `input_failures`.
Missing/mismatched bundles block; raw Git reconstruction is not a fallback.
It replays the BASE collector and checks snapshots, source digest and every files
API path/status against a NUL-delimited Git manifest. Safe blob IDs/counts survive.
The plan/request binds scope and source/context/diff hashes; metadata is data.
Header-only renames require equal Git blob IDs, without reading bodies, before
adding 100% similarity evidence; actual mode changes are retained. Omitted content
changes block. `collector_diff_sha256` identifies replay bytes; `diff_sha256`
identifies the completed metadata supplied to the protocol. Shared bounds are in
[Limits and checks](#limits-and-checks).

ADR-004 state/plan additions, modifications and renames block. Eligible deletion
bodies stay withheld. API-omitted oversized text deletions use explicit `path_only`
metadata and actual tree mode without fetching old bodies. Mixed input retains all
reviewable text. The eligible deletion-only result is reserved for the trusted
workflow shortcut; ordinary empty input never receives role PASS. MRA installs no
generic `role-input-scope.json` or exclusions-only opt-in. Workflow/E2E tests
cover this custody and the safe deletion-only artifacts.

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

<a id="provenance-planned"></a>

### Provenance

`--provenance FILE` supplies a JSON object. This table is the canonical field
contract; library checks and trusted-producer duties are distinct.

| Field | Required for | Meaning and owner |
| --- | --- | --- |
| `head_sha`, `base_sha` | Every supplied provenance object | Lowercase 40-hex CLI revisions; the library checks equality. `base_sha` identifies the trusted checkout and policy source. |
| `diff_sha256` | Every supplied provenance object | SHA-256 of the exact bytes supplied through `--diff`, after approved filtering. The library recomputes it; an approved empty input hashes empty bytes. |
| `merge_base_sha` | Generic Git preparer | Immutable comparison origin verified by the trusted preparer. |
| `raw_diff_sha256` | Generic Git preparer | Hash of its complete, unfiltered Git diff before policy exclusions. The preparer computes/verifies this evidence; the library does not recover withheld input to recompute it. |
| `scope_paths` | Generic Git preparer; exclusions-only opt-in | Complete original path set, independently derived from Git by the preparer, including excluded paths. |
| `excluded_paths` | Generic Git preparer; exclusions-only opt-in | Paths excluded by the verified BASE policy; empty when none. For exclusions-only, the library requires equality with nonempty `scope_paths`. |
| `input_policy_sha256` | Generic preparer using a policy; exclusions-only opt-in | Hash of exact committed BASE policy bytes; null without a policy. For exclusions-only the library hashes `--policy FILE` and requires a match. |
| `scope_exception` | Exclusions-only opt-in | Exactly `configured_exclusions_only`, with explicit CLI opt-in and empty diff/reviewable paths; absent or null for ordinary review. |
| `input_failures` | Optional | Static codes matching `[a-z][a-z0-9_:.-]{0,63}`; any code blocks. |
| `path_only` | Optional collector-approved metadata-only deletions | Path list permitting deletion-metadata review without bodies; eligibility remains the trusted collector's responsibility. |

`diff_sha256` and `raw_diff_sha256` describe different processing stages and can
differ. They are not interchangeable names. The generic producer must supply its
listed fields in addition to the common library envelope. Project adapters may
retain additional evidence; MRA uses its approved collector view and never
reconstructs withheld state bodies merely to populate the generic raw-diff field.
Provenance is bound into request/plan fingerprints as data; invalid envelope
values block and stored values are scrubbed. These hashes do not authenticate an
arbitrary caller or independently establish Git membership.

## Coverage and lifecycle

Codex/Claude are required for reviewable source; trusted routing may deactivate
irrelevant Kiro roles. Unknown paths route conservatively. Failed output is never
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
the first result and block. Finish writers before aggregation. Reissue archives
32 prior results in `slot/TAG-attempts.json`; model-selection/fallback/quota/preflight
failures block until new preparation. Summaries retain history. All `*.flag` files
block except the aggregator's own root `coverage-severe.flag`, which it rewrites from
current evidence; upstream flags are never exempt. `failure_codes` is canonical; `failures` aliases it.

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
Offline CI: `.github/workflows/pr-review-roles-tests.yml`. Workflow integration and exact-HEAD
publication tests are included; offline success proves
no live provider execution.

Sol replaces this repository's legacy Terra slot; application
inference models remain unchanged.

MRA retains ADR-004 collector/state-deletion custody and its deletion-only shortcut.
These stages do not configure generic exclusions-only scope for MRA (ADR-005).

Exclusions-only review requires both `--allow-exclusions-only --policy FILE`.
The planned generic source is the reviewed schema-1
`scripts/pr-review/role-input-scope.json` blob at pinned BASE. `FILE` is the trusted
caller's byte-identical local copy. Preparation will retain those verified bytes
as `WORK/exclusions-policy.json`, a generated private validation copy rather than
another committed policy. Both copies must match `input_policy_sha256` of the BASE
blob; aggregation will recheck the retained WORK copy. Missing or mismatched opt-in
blocks. The caller, not this library, must verify the BASE source, complete Git
scope and approved exclusions. MRA does not enable this generic policy.

The generic BASE preparer must supply the fields and source checks in the
[canonical provenance table](#provenance-planned). Candidate/model assertions
cannot establish these facts. Incomplete evidence fails closed. As recorded in ADR-005, the library does
not impose a universal file-type denylist: reviewed generated-code exclusions
remain possible. MRA instead retains ADR-004's specific mandatory deny rules.

A valid result cannot be reissued to discard findings or uncertainty. Start a new
preparation for a new review; failed attempts retain their diagnostic history.

Codex/Claude rows use Bedrock Runtime IDs; Kiro rows use Kiro catalog aliases.
Local Codex on Mantle uses `openai.gpt-6-astra`; these namespaces are distinct.

Configured chair fallback may recover from transient throttling within existing
attempt/turn/time bounds; hard account/monthly/credit/overage limits still stop it.

MRA retains the legacy `PANEL_CELL_CAP=20000` per-slot evidence budget. Before
chair invocation, oversized validated response data blocks without truncation;
no ADP-style total cap is substituted. Model JSON, with terminal display controls removed, reaches `record` through
a mode-0600 temporary file outside WORK, removed even if recording fails. Only
validated/scrubbed results and scrubbed diagnostics remain in review artifacts.

## Workflow and artifacts

Immediately after checkout, CI rejects a symlink WORK and recreates `/tmp/pr-review`
before CLI checks or collection. Original files API responses are deleted before
providers run; current omission/preflight flags survive coordination. Missing or
invalid required coverage produces deterministic FAIL; the chair cannot waive it.
The eligible deletion-only shortcut invokes no provider and publishes safe collection
metadata rather than invented role results. Posting rechecks the current PR HEAD.

Publish `role-source.json`, plan/summary, issued receipts, attempt ledgers, results
and timing metadata. Request bodies, role diffs and original model output are private.
Each attempt uses its persisted nonce-bound request; interrupted locks require fresh
work. Full helper contracts are defined above and in each command's `--help`.

Responses require `head_sha`, `role`, `scope_complete`, all `reviewed_paths`, evidence
`checks`, `findings` and `uncertainties`. Findings carry severity/path/condition/evidence.
One JSON fence or Kiro `>` prefixes are accepted; extra prose and duplicate keys fail.
Validated paths stay exact while decoded credential values are scrubbed. Sensitive
containers are scanned without evaluation: complete boundaries preserve outside text;
ambiguous expression tails consume the remainder and cannot retain a chair PASS.
Bullets, links or closing fences can resemble continuations; avoid sensitive
assignment examples in the final report.

MRA retains its portable control stripper because its legacy `lib.sh` lacks one.
Terminal formatting is removed before JSON validation without masking path values;
credential masking follows validation. Generic exclusions in shared E2E tests exist
only in temporary fixtures. They do not configure exclusions-only review for MRA.

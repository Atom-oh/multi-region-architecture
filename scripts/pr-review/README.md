# Specialist review protocol

**Inactive executor bootstrap.** The offline protocol and common executors are
installed. MRA's required guard profile blocks preparation until the separate
collector adapter arrives in PR #55; activation follows in PR #56. The operational
workflow remains on its legacy path.

| Tag | Requested model | Scope |
| --- | --- | --- |
| codex | `global.openai.gpt-6-astra` | Implementation/tests |
| kiro-fable | `claude-opus-5` | AWS/IAM/network |
| kiro-sol | `gpt-5.6-sol` | Deployment/contracts/recovery |
| claude-self | `global.anthropic.claude-fable-5-1` | Auth/data/API/ADR |

`kiro-fable` means Opus. The `ROLES` constant in `role_review.py` defines
protocol tags; `run-panel.sh` defines the existing legacy slot labels.
Kiro/Bedrock IDs differ. English is requested, not validated; configured IDs do not
attest model weights.

## Slot mapping (planned)

| Protocol tag | Legacy `run-panel.sh` slot | Model selection |
| --- | --- | --- |
| `kiro-fable` | `kiro-opus` | `claude-opus-5` remains selected |
| `kiro-sol` | `kiro-gpt` | Planned `gpt-5.6-terra` → `gpt-5.6-sol` |

These are different label namespaces. The protocol tag does not rename the
legacy slot; the activation change selects the new role-based execution path.

## Installed common libraries

`run-specialists.sh` coordinates one role per applicable tag; `run_role.py` sends
issued requests, validates process/transport outcomes and records scrubbed results.
Codex validates JSONL events and its private final-output file. Kiro uses an empty
catalog and fixed no-tools canary in an isolated environment. `synthesize_roles.py`
selects deterministic output or bounded chair adjudication.

`prepare_roles.py` validates a pinned BASE checkout. Its generic branch can load a
committed, byte-matched `prepare_context_roles.py`; absence preserves root context.
No such repository-specific helper is installed here. MRA requires its separate
collector adapter before selecting these executors; do not replace ADR-004's
approved input with generic raw Git diff. See [ADR-005](../../docs/decisions/ADR-005-specialist-review-protocol.md).

## MRA bootstrap guard and commands

`role-project.json` is installed now as a required guard. Its named MRA adapter
arrives in the next stage; until then preparation fails before any raw Git diff
fallback. The profile already enforces 600-second chair attempts, 8/12 turns and
the mandatory deny baseline. No workflow selects these libraries yet.

After the adapter is installed, invoke from the pinned BASE checkout with
`HEAD_SHA`, `BASE_SHA` and `GH_REPO` set:

| Entry point | Arguments |
| --- | --- |
| `prepare_roles.py` | `--prepared-diff BUNDLE/panel.diff --work WORK` |
| `run-specialists.sh` | `BUNDLE/panel.diff LEGACY_LENSES WORK` (second argument reserved/unused) |
| `run_role.py` | `--work WORK --tag TAG` |
| `synthesize_roles.py` | `--work WORK --output REPORT` |

`--prepared-diff` is input for the configured project adapter. Generic consumers
instead derive immutable Git scope and apply their BASE policy; MRA's required
profile prevents that generic fallback. Claude's specialist command disables
built-in tools with `--tools ""` and ignores unprovided MCP configuration with
`--strict-mcp-config`; the command and token removal have regression coverage.

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

Run `python3 -m unittest discover -s scripts/pr-review -p test_role_review.py`.
Offline CI: `.github/workflows/pr-review-roles-tests.yml`. Activation also needs
executor/adapter, limit and exact-HEAD publication tests; offline success proves
no live provider execution.

Sol replaces this repository's legacy Terra slot at activation; application
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

MRA retains the legacy `PANEL_CELL_CAP=20000` per-review evidence budget. Before
chair invocation, oversized validated response data blocks without truncation;
no ADP-style total cap is substituted. Original model JSON reaches `record` through
a mode-0600 temporary file outside WORK, removed even if recording fails. Only
validated/scrubbed results and scrubbed diagnostics remain in review artifacts.

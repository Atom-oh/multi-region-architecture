# MRA specialist input adapter

This activation workflow selects `ROLE_REVIEW=1` and consumes the MRA adapter and
explicit chair policy. It follows the protocol, common-executor and MRA-adapter stages; see
[ADR-005](../../docs/decisions/ADR-005-specialist-review-protocol.md).
Release follows current-HEAD review and required CI. Offline checks do not establish
live inference or deployment.

The workflow recreates `/tmp/pr-review` immediately after checkout, before CLI
checks or input preparation. A symlink is rejected first. Current preparation and
preflight failure flags remain intact for aggregation.

## Trusted interface

The adjacent `role-project.json` selects `prepare_project_roles.py`, canonical
`CLAUDE.md` plus `mra-review-context.md`, and the existing chair policy. The shared
preparer invokes this hook before selecting default context or generating any
raw Git diff:

```python
prepare(head, base, merge_base, work, supplied_diff) -> {
    "diff": bytes,
    "paths": list[str],
    "context": bytes,
    "provenance": dict,
    "input_failures": list[str],
}
```

`supplied_diff` is the complete `panel.diff` next to `collection.json`.
Missing, mismatched or invalid bundles raise `ValueError`; never fall back to raw
Git input. Preserve failures as blocked results before any provider invocation.
The metadata is review evidence, not instructions.

The shared CLI names the caller-provided file `--prepared-diff`:

```bash
python3 scripts/pr-review/prepare_roles.py \
  --prepared-diff /tmp/pr-review-collect/panel.diff --work /tmp/pr-review
```

`run-specialists.sh` forwards its first argument through that flag. Pair the adapter
with the shared runtime revision that loads `role-project.json`; an older generic
preparer is not a compatible fallback.

The hook checks immutable HEAD/base/merge-base identifiers, both collection
snapshots, the collector's BASE source digest, every API path/status against a
NUL-delimited Git manifest, and exact collector replay. It validates complete
text hunks without using diff headers to decide file identity.

## Issued requests and artifacts

Before each attempt, `role_review.py issue --work <work> --tag <tag>` persists the
framed `requests/<tag>.prompt` and `requests/<tag>.input`, plus
`slot/<tag>-request.json` containing their hashes, invocation nonce and plan binding.
Executors send those issued bytes. `record --nonce` and aggregation require the
matching receipt; a self-declared nonce cannot validate a result. Re-preparation
clears old result/request/timing JSON but preserves upstream failure flags.
Issuing and recording use a per-tag operation lock; an interrupted operation
requires a fresh workspace. Finish result writers before aggregation.

Codex uses `--json` and an attempt-specific `--output-last-message` file in its
private temporary directory. The executor validates stream completion and reads
that final reply unchanged. Tool/progress events cannot become review output;
native error events still undergo terminal-diagnostic checks. Missing final output,
failed turns or nonzero exit remain failures. The temporary file is not uploaded.

Uploads include the receipt and `role-source.json` alongside result/plan/summary
metadata. Framed request bodies are not uploaded. The trusted deletion-only path
has collection evidence instead of invented provider receipts.

Valid findings cannot be discarded: this runtime rejects reissue of a valid
result before changing its result or receipt. Reissuing after a failed result
retains it in `slot/<tag>-attempts.json`.
Terminal model failures create sticky `slot/role-<tag>-terminal.flag`, so a later
clean result cannot waive them. The summary exposes `attempt_history`. Uploads
include the ledger with receipt/source metadata. Fresh preparation clears previous
attempt records and protocol-owned terminal flags; upstream failures remain.

## Protocol contract

`python3 scripts/pr-review/role_review.py COMMAND --help` lists required flags.

| Command | Files and result |
| --- | --- |
| `prepare` | Diff/context, HEAD/base and work produce `role-plan.json` and `roles/<tag>.txt/.diff`. |
| `issue` | Work/tag produce the framed request and matching receipt described above. |
| `record` | Work/tag, output/stderr, exit code and issued nonce produce `slot/<tag>-result.json`. |
| `aggregate` | Validates receipts, scope and fingerprints; writes `role-summary.json`, `responded.txt` and `chair-mode.txt`. |

`--paths FILE` contains a UTF-8 JSON array of unique repository-relative reviewable paths;
renames use destinations while collector provenance covers both names.
`--provenance FILE` contains a JSON object with matching lowercase 40-hex `head_sha`/`base_sha` and a
`diff_sha256` of the exact raw input bytes. Optional `path_only` identifies approved
metadata-only deletions. Optional `input_failures` codes must match
`[a-z][a-z0-9_:.-]{0,63}` and always block; invalid provenance also blocks.
Persisted values are scrubbed.

Responses have exactly `head_sha`, `role`, `scope_complete`, `reviewed_paths`,
`checks`, `findings` and `uncertainties`. Complete scope means every expected path,
with at least one `{path, evidence}` check. Findings require
`severity` (`CRITICAL|MAJOR|MINOR|INFO`), `path`, `condition` and `evidence`.
Uncertainties are strings. A single JSON fence or Kiro `>` prefixes are allowed;
extra prose, duplicate keys and invalid scope are rejected.

Exit 2 is blocked, not permission for the chair to waive coverage. Aggregation
produces deterministic FAIL and `coverage-severe.flag` for blocked input/results.
Exit 0 with `chair-mode.txt=deterministic` permits a complete, uncontested summary
(Minor/Info remain visible); `review` requires adjudication of Critical/Major
candidates or uncertainties. Required missing, stale or invalid results block.
All `*.flag` files block except the generated root `coverage-severe.flag`.
`failure_codes` is canonical; `failures` is its alias. Reports retain role
activation reasons and attempt history. At most 32 prior results may be archived.

The generic `configured_exclusions_only` outcome requires explicit
`--allow-exclusions-only --policy FILE`, empty diff/paths and matching scope lists.
The engine hashes actual schema-1 policy bytes against `input_policy_sha256`,
retains `exclusions-policy.json` and rechecks that anchor during aggregation.
Its caller MUST verify the policy's trusted BASE source and complete Git scope;
the library does not discover repository membership. MRA does not enable this
policy or weaken ADR-004. See ADR-005 for the approved exception's PASS semantics.

## Collector bundle

The trusted caller resolves/fetches the immutable Git objects and collects all
GitHub files API pages between two PR snapshot checks. Each snapshot file contains
only `{"head_sha": "<40-hex>", "base_sha": "<40-hex>"}`.

```bash
python3 scripts/pr-review/prepare_project_roles.py \
  --files /tmp/pr-files.json \
  --before /tmp/pr-before.json --after /tmp/pr-after.json \
  --head "$HEAD_SHA" --base "$BASE_SHA" --merge-base "$MERGE_BASE_SHA" \
  --output /tmp/pr-review-collect
```

This runs the existing `collect-diff.sh`. The retained bundle has its approved
diff and sanitized files API records. Excluded patches, including deleted state
contents, are removed before persistence. A separate `collection-meta.json` excludes all patches and is safe to include
with coverage/exception artifacts. Safe API blob IDs and change counters remain
in public and fingerprinted scope metadata. Temporary classifier inputs are destroyed
before returning. The caller must retain the existing cleanup of its
original raw API response files before reviewers run.

`paths` contains reviewable filenames in collector order. Provenance records
`scope_paths` (including both rename paths), per-file status/classification,
excluded entries, snapshot/source/context/diff hashes and any accepted exception.
This provenance is bound into trusted plan/request/result fingerprints and included
with summary evidence. No changed path may disappear merely because it is absent
from provider text.

API-omitted oversized text deletions remain metadata-only. The adapter adds their
actual Git tree mode to the collector's deletion record so the existing engine
accepts it; it never fetches the old body. Both collector and prepared diff hashes
are recorded, and `path_only` identifies these entries. Reviewers must see that
the deletion was assessed without its contents.

## Exceptions, limits and chair

Only ADR-004's eligible deletion-only case returns
`provenance.exception == "adr004_deletions_only"` with empty diff/paths. The caller
preserves the existing no-provider shortcut and uploads explicit exception
evidence. It does not fabricate role results or pass an empty diff to ordinary review.
Other empty views return `no_reviewable_input`.

All reviewable text is retained. Input beyond 95,000 bytes or 3,000 lines reports
`input_failures`, without truncation. Context combines only BASE source bytes;
candidate sources are checked for availability/size but never become instructions.
The context ceiling stays 24,000 bytes and the shared request ceiling still applies.
There is no automatic chunking or budget increase.

`role-project.json` requires 600-second chair attempts, 8 primary turns and 12
fallback turns. Read/Grep/Glob remain the allowed set; the Bash/Write/Edit/
NotebookEdit/WebFetch/WebSearch/Task deny baseline must always be sent. The shared
chair enforces these explicit settings even if the legacy shell file is removed,
and rejects attempts to disable or increase the limits. This preserves ADR-004
independently of regex extraction.

The approved specialist roster is Codex `global.openai.gpt-6-astra`, Kiro
`claude-opus-5` and `gpt-5.6-sol`, and Claude
`global.anthropic.claude-fable-5-1`. The legacy Terra setting is not the specialist
roster. These IDs target CI's Bedrock Runtime provider; local Mantle uses the distinct
`openai.gpt-6-astra` ID. Configured identity and offline tests do not attest live inference.
For reviewable input, Codex (`implementation`) and Claude (`requirements`) are
always required and receive all paths. Trusted routing can deactivate irrelevant
Kiro roles; model failures never create an exemption.

Run `python3 -B -m unittest -v test_project_roles test_project_integration_roles`
from this directory, followed by the shared runtime and existing collector tests.
The integration suite executes the real shared entrypoints with local Git and fake
CLIs: missing bundles block before raw diff generation, provenance is fingerprinted,
withheld state stays out of provider/artifact input, and mandatory chair arguments
survive legacy-script removal. Invalid budget overrides must fail before a call.

During shared-core integration, `ROLE_REVIEW_TEST_CORE=/path/to/shared/core` selects
the candidate runtime for temporary test fixtures only. It neither changes production
configuration nor overwrites this repository's shared files. Run the same suite
without that override after copying the reviewed common runtime into the repository.

The activation-only `test_project_workflow_roles` suite executes the workflow's
actual collection, prompt, review and gate blocks. It checks mixed state deletion
privacy, raw-response cleanup, deletion-only provider skipping and the declared
artifact-upload paths using local Git and fake CLIs.

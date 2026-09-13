# ADR-005: Activate specialist review after the protocol-only stage

## Status

Accepted (2026-09-13). Separate protocol, common-executor and MRA-adapter stages
precede this final workflow activation and its end-to-end tests. Code and offline tests do not establish live
deployment or inference.

## Context

The specialist design assigns distinct responsibilities while retaining independent
Codex/Claude coverage and explicit failures. Combining protocol, executors, project
adaptation and activation makes the native review input too large. The rollout
therefore separates protocol, common executors, MRA adaptation and activation without
increasing review budgets or removing meaningful tests.

Multi-Region Architecture (MRA) already has operational contracts for collector classification, sensitive
deletions and bounded adjudication. Adding a protocol must not silently replace
those controls or imply that a new workflow is active.

## Decision

Phase one introduced `role_review.py`, `test_role_review.py`, protocol documentation
and their dedicated offline test workflow. The library prepares role inputs,
validates responses and aggregates coverage. It binds supplied provenance and
invocation-nonce metadata; it performs no Git fetch, provider call or publication.
The [module README](../../scripts/pr-review/README.md) now describes the integrated
MRA input contract.

The library blocks incomplete input and diffs exceeding 95,000 bytes or 3,000
lines, without prefix credit. Context and complete-request limits also apply.
There is no automatic chunking or budget increase. The activated review path
applies these limits to the complete approved collector view.

The workflow selects `ROLE_REVIEW=1` from a pinned BASE checkout. Immediately
after checkout it rejects a symlink WORK and recreates the review directory before
CLI checks or input collection. Current upstream failure flags survive coordination. Provider
executors, the project-policy loader, MRA adapter and chair integration consume
the protocol. Canonical BASE CLAUDE.md plus a bounded ADR summary supplies context;
candidate context is validated but never becomes instructions.

The existing files API collector still decides which contents may be reviewed.
The adapter binds its complete view to head/base/merge-base identifiers, before/
after snapshots, the BASE collector digest and Git's NUL-delimited path/status
manifest. Raw Git reconstruction is not a fallback. Safe provenance reaches
prompts, plan/request fingerprints and summary artifacts. Deleted state contents
remain withheld; metadata-only text deletions retain their explicit scope.

Required roles receive one responsibility each, with fresh invocation framing.
Codex and Claude provide independent family coverage; deterministic routing
selects the Kiro roles. Kiro uses an empty catalog, isolated environment and
successful no-tools canary. Invalid output, quota/model failures or incomplete
required coverage block; configured model identities are not execution attestations.

Complete uncontested results produce a deterministic summary. Valid substantive
candidates or uncertainties go to a bounded chair. The project policy enforces
600-second attempts, 8/12 turns and the mandatory tool deny baseline independently
of the legacy shell file. A chair cannot waive incomplete coverage. Valid findings cannot be discarded;
this runtime rejects reissue of a valid result.

**Approved generic exclusions-only result.** Repository maintainers approve the
scope policy through review of the committed BASE configuration. The trusted
preparer, never a model response, may select `configured_exclusions_only` when
all changed paths are covered by that policy. The prepared diff and reviewable
path list must be empty; nonempty `scope_paths` and `excluded_paths` must match,
and `input_policy_sha256` must identify the verified BASE policy. Explicit
`--allow-exclusions-only --policy FILE` anchors its exact bytes; the caller MUST
verify BASE policy provenance and complete Git scope. Missing,
unknown or accidentally empty input and provider failures do not qualify.

For this approved case the protocol may make all roles inactive, invoke no models,
and produce a deterministic `NOT_APPLICABLE` explanation followed by
`VERDICT: PASS`. This PASS means the approved scope check passed, not that models
reviewed the change. The report must disclose the excluded paths and policy hash.
If any reviewable input remains, the independent primary-role requirement applies.

**Policy artifacts (planned).** For generic consumers, the reviewed source is
`scripts/pr-review/role-input-scope.json` in the pinned BASE commit. The trusted
caller passes a byte-identical local copy using `--policy FILE`. Preparation will
retain the verified bytes as `WORK/exclusions-policy.json`: a generated private
validation copy, not a second committed policy. `input_policy_sha256` hashes the
exact BASE policy bytes; both local copies must match it. Aggregation will recheck
the retained WORK copy against that digest. The caller still owns verification of
the BASE source and complete Git scope.

**Required generic integration.** Before requesting this exception, the trusted
BASE preparer must verify its checkout, read the policy blob from `base_sha`, and
derive the complete changed-path set from immutable Git objects. It must supply
the generic and exception fields in the README's
[canonical provenance table](../../scripts/pr-review/README.md#provenance-planned).
That table distinguishes the complete source diff from the approved protocol input
and specifies which component verifies each hash.
Candidate-supplied policy/scope assertions and model output are not authoritative.
Missing or incomplete evidence must fail closed, never become NOT_APPLICABLE.

**Accepted boundary.** Hashes bind the supplied evidence; they do not authenticate
an arbitrary caller. Git/source verification belongs to the trusted BASE preparer,
not the offline library. A universal file-type denylist is deliberately absent:
reviewed policies can legitimately exclude generated code, including generated
IaC. Consumer-specific eligibility belongs to that reviewed policy and collector.
A defective trusted collector or approved policy remains a reviewable integration
risk, not a guarantee supplied by the hash check. MRA authorizes none of this
generic exclusion policy; its separate ADR-004 deny rules remain mandatory.

This generic library capability does not broaden MRA's ADR-004 exception. MRA
continues to use its custom files API collector, state-body withholding and the
narrow deletion-only workflow shortcut. These MRA stages do not introduce a
`role-input-scope.json` policy or select `configured_exclusions_only` for MRA.

**Scoped context validation.** The adapter requires the immutable BASE, HEAD and
merge-base objects to be available; a targeted shallow fetch suffices. It may read
only the fixed candidate context documents as data to reject missing/oversized
context before merge. Candidate text is never executed or used as instructions.
This narrow check qualifies the historical blanket wording about HEAD-blob reads
in ADR-004; it does not authorize retrieval of withheld state/plan bodies. Adapter
source order and the JSON profile are bound by the preparer and MRA regression tests.

Existing decisions remain in force:

- [ADR-002](ADR-002-pr-review-kiro-fs-read-risk.md): preserve trusted execution and
  credential boundaries. A configured model or tool flag alone is not runtime proof.
- [ADR-003](ADR-003-eks-mgmt-ownership-handoff.md): management-cluster state custody
  remains with AWS-Demo-Platform; this PR changes no infrastructure ownership.
- [ADR-004](ADR-004-pr-review-empty-diff-exception.md): retain files API classification,
  both rename paths, state/plan deny rules, deletion-content withholding and the
  narrowly eligible deletion-only exception. Preserve the 600-second chair limits,
  8/12 turn caps and mandatory tool deny baseline in the activated path.

## Consequences and verification

The operational workflow now delegates to the specialist runtime. Collector
classification, deletion-only eligibility and infrastructure custody are preserved.
The trusted deletion-only shortcut invokes no provider and uploads safe collection
metadata; it does not fabricate successful role responses. Public posting still
checks the current PR HEAD.

Run
`python3 -B -m unittest discover -s scripts/pr-review -p 'test_*role*.py' -v`
and `bash scripts/pr-review/test-collect-diff.sh`. Integration tests exercise the
real entrypoints and workflow blocks with local Git and fake CLIs, including
missing-bundle rejection, state privacy and chair controls after legacy-script
removal. Current-HEAD review and required CI still precede release.
